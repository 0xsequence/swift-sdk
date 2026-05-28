import SwiftUI
import Combine
import OMS_SDK
#if os(iOS)
import UIKit
import SafariServices
#elseif os(macOS)
import AppKit
#endif

// MARK: - Clipboard helper

enum Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }
}

// MARK: - Chains

private let supportedNetworks: [Network] = Network.supportedNetworks
private let oidcRedirectUri = "omsclientswiftdemo://auth/callback"

struct SafariAuthSession: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

private enum DemoAuthError: Error, LocalizedError {
    case invalidAuthorizationURL

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL:
            return "The authorization URL could not be opened."
        }
    }
}

@MainActor
fileprivate final class FeeOptionSelectionRequest: Identifiable {
    let id = UUID()
    let options: [FeeOptionWithBalance]

    private var continuation: CheckedContinuation<FeeOptionSelection?, Error>?

    init(
        options: [FeeOptionWithBalance],
        continuation: CheckedContinuation<FeeOptionSelection?, Error>
    ) {
        self.options = options
        self.continuation = continuation
    }

    var isResolved: Bool {
        continuation == nil
    }

    func select(_ option: FeeOptionWithBalance) {
        resume(returning: option.selection)
    }

    func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }

    private func resume(returning selection: FeeOptionSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selection)
    }
}

// MARK: - Styling

private var appBackgroundColor: Color {
    #if os(iOS)
    Color(.systemGroupedBackground)
    #elseif os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #endif
}

private var panelBackgroundColor: Color {
    #if os(iOS)
    Color(.secondarySystemGroupedBackground)
    #elseif os(macOS)
    Color(nsColor: .textBackgroundColor)
    #endif
}

private var panelBorderColor: Color {
    #if os(iOS)
    Color(.separator).opacity(0.45)
    #elseif os(macOS)
    Color(nsColor: .separatorColor).opacity(0.8)
    #endif
}

private var fieldBackground: some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(panelBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
}

// MARK: - USDC

/// USDC contract on the configured chain.
private let usdcContractAddress = "0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582"

/// USDC has 6 decimals. Raw balance is an atomic-unit integer string.
private func formatUSDCBalance(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "0.00" }

    let decimals = 6
    let padded = trimmed.count <= decimals
        ? String(repeating: "0", count: decimals - trimmed.count + 1) + trimmed
        : trimmed
    let splitIdx = padded.index(padded.endIndex, offsetBy: -decimals)
    let whole = String(padded[..<splitIdx])
    let frac = String(padded[splitIdx...].prefix(2))

    let wholeStripped = String(whole.drop(while: { $0 == "0" }))
    let wholeOut = wholeStripped.isEmpty ? "0" : wholeStripped
    return "\(wholeOut).\(frac)"
}

private func nativeTokenSymbol(for network: Network) -> String {
    network.nativeTokenSymbol
}

private func formatNativeTokenBalance(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "0" }

    let formatted = trimmed.contains(".")
        ? trimmed
        : ((try? formatUnits(value: trimmed, decimals: 18)) ?? "0")
    return trimBalanceDisplay(formatted, maxFractionDigits: 6)
}

private func trimBalanceDisplay(_ value: String, maxFractionDigits: Int) -> String {
    guard maxFractionDigits > 0 else {
        return String(value.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
    }

    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return value }

    let whole = parts[0].isEmpty ? "0" : String(parts[0])
    let fraction = String(parts[1])
    let limitedFraction = String(fraction.prefix(maxFractionDigits))
    let trimmedFraction = String(limitedFraction.reversed().drop(while: { $0 == "0" }).reversed())

    guard !trimmedFraction.isEmpty else {
        let hasTinyRemainder = whole == "0" && fraction.dropFirst(maxFractionDigits).contains { $0 != "0" }
        if hasTinyRemainder {
            return "<0.\(String(repeating: "0", count: maxFractionDigits - 1))1"
        }
        return whole
    }

    return "\(whole).\(trimmedFraction)"
}

// MARK: - App State

enum AppScreen {
    case login
    case confirmCode
    case walletSelection(PendingWalletSelection)
    case wallet
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var screen: AppScreen = .login
    @Published var isLoading: Bool = false
    @Published var error: GenericAppError?
    @Published var safariAuthSession: SafariAuthSession?
    @Published fileprivate var feeOptionSelectionRequest: FeeOptionSelectionRequest?
    @Published var useManualWalletSelection: Bool = false
    @Published var oms: OMSClient = OMSClient(
        publishableKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE",
        projectId: "proj_014kg56dc0a75"
    )

    init() {}

    private var walletSelectionBehavior: WalletSelectionBehavior {
        useManualWalletSelection ? .manual : .automatic
    }

    func checkSession() async {
        let hasSession = !oms.wallet.walletAddress.isEmpty
        screen = hasSession ? .wallet : .login
    }

    func signOut() {
        do {
            try oms.wallet.signOut()
            safariAuthSession = nil
            screen = .login
        } catch {
            present(error)
        }
    }

    // MARK: Login

    func submitLogin(input: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await oms.wallet.startEmailAuth(email: input)
            screen = .confirmCode
        } catch {
            present(error)
        }
    }

    func startGoogleRedirectAuth() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let started = try await oms.wallet.startOidcRedirectAuth(
                provider: OidcProviders.google(),
                redirectUri: oidcRedirectUri
            )
            guard let authorizationUrl = URL(string: started.authorizationUrl) else {
                throw DemoAuthError.invalidAuthorizationURL
            }

            #if os(iOS)
            safariAuthSession = SafariAuthSession(url: authorizationUrl)
            #elseif os(macOS)
            NSWorkspace.shared.open(authorizationUrl)
            #endif
        } catch {
            present(error)
        }
    }

    func handleOpenURL(_ url: URL) async {
        do {
            let result = try await oms.wallet.handleOidcRedirectCallback(
                url.absoluteString,
                walletSelection: walletSelectionBehavior
            )

            switch result {
            case .completed:
                safariAuthSession = nil
                screen = .wallet
            case .walletSelection(let pendingSelection):
                safariAuthSession = nil
                screen = .walletSelection(pendingSelection)
            case .notOidcRedirectCallback, .noPendingAuth:
                break
            case .failed(let error):
                safariAuthSession = nil
                present(error)
            }
        } catch {
            safariAuthSession = nil
            present(error)
        }
    }

    // MARK: Confirm Code

    func submitConfirmCode(code: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await oms.wallet.completeEmailAuth(
                code: code,
                walletSelection: walletSelectionBehavior
            )
            switch result {
            case .walletSelected:
                screen = .wallet
            case .walletSelection(let pendingSelection):
                screen = .walletSelection(pendingSelection)
            }
        } catch {
            present(error)
        }
    }

    func selectWallet(_ wallet: Wallet, from pendingSelection: PendingWalletSelection) async {
        await completeWalletSelection {
            try await pendingSelection.selectWallet(walletId: wallet.id)
        }
    }

    func createWallet(from pendingSelection: PendingWalletSelection) async {
        await completeWalletSelection {
            try await pendingSelection.createAndSelectWallet()
        }
    }

    func cancelWalletSelection() {
        isLoading = false
        safariAuthSession = nil
        do {
            try oms.wallet.signOut()
        } catch {
            present(error)
        }
        screen = .login
    }

    private func completeWalletSelection(
        _ operation: () async throws -> WalletActivationResult
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await operation()
            screen = .wallet
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        if let appError = GenericAppError(error) {
            self.error = appError
        }
    }

    func selectFeeOption(_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection? {
        guard !options.isEmpty else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            feeOptionSelectionRequest?.cancel()
            feeOptionSelectionRequest = FeeOptionSelectionRequest(
                options: options,
                continuation: continuation
            )
        }
    }

    fileprivate func clearFeeOptionSelectionRequest(_ request: FeeOptionSelectionRequest) {
        guard feeOptionSelectionRequest?.id == request.id else { return }
        feeOptionSelectionRequest = nil
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        Group {
            switch vm.screen {
            case .login:
                LoginWindow()
            case .confirmCode:
                ConfirmCodeWindow()
            case .walletSelection(let pendingSelection):
                WalletSelectionWindow(pendingSelection: pendingSelection)
            case .wallet:
                WalletWindow()
            }
        }
        .environmentObject(vm)
        .genericErrorWindow(error: $vm.error)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
        .task {
            await vm.checkSession()
        }
        .onOpenURL { url in
            Task {
                await vm.handleOpenURL(url)
            }
        }
        #if os(iOS)
        .sheet(item: $vm.safariAuthSession) { session in
            SafariView(url: session.url)
                .ignoresSafeArea()
        }
        #endif
    }
}

// MARK: - Login Window

struct LoginWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var inputText: String = ""
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                AuthWelcomeHeader(
                    subtitle: "Sign in to continue to your wallet."
                )
                .padding(.top, 64)

                FieldGroup(title: "Email address", titleStyle: .secondary) {
                    TextField("you@example.com", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(fieldBackground)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                .padding(.top, 32)

                ManualWalletSelectionToggle()
                    .padding(.top, 16)

                Spacer()

                Button {
                    Task { await vm.submitLogin(input: inputText) }
                } label: {
                    label(for: "Continue", loading: vm.isLoading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(inputText.isEmpty || vm.isLoading)

                Button {
                    Task { await vm.startGoogleRedirectAuth() }
                } label: {
                    label(for: "Continue with Google", systemImage: "globe", loading: vm.isLoading)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isLoading)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .onAppear { emailFocused = true }
    }
}

// MARK: - Confirm Code Window

struct ConfirmCodeWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var codeText: String = ""

    var body: some View {
        NavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                AuthWelcomeHeader(
                    subtitle: "Verify your email to finish signing in."
                )
                .padding(.top, 64)

                Text("Enter the 6-digit code sent to your email.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                VerificationCodeInput(code: $codeText)
                    .padding(.top, 32)

                ManualWalletSelectionToggle()
                    .padding(.top, 24)

                Spacer()

                Button {
                    Task { await vm.submitConfirmCode(code: codeText) }
                } label: {
                    label(for: "Verify", loading: vm.isLoading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(codeText.count != 6 || vm.isLoading)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Wallet Selection Window

struct WalletSelectionWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    let pendingSelection: PendingWalletSelection

    var body: some View {
        NavigationScreenContainer(maxWidth: 520) {
            VStack(alignment: .leading, spacing: 0) {
                AuthWelcomeHeader(
                    subtitle: "Select a wallet to finish signing in."
                )
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    walletsSection
                    createSection

                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.top, 32)

                Spacer()

                Button {
                    vm.cancelWalletSelection()
                } label: {
                    label(for: "Cancel", systemImage: "xmark", loading: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isLoading)
                .padding(.bottom, 24)
            }
        }
    }

    private var walletsSection: some View {
        FieldGroup(title: "Wallets", titleStyle: .secondary) {
            VStack(spacing: 8) {
                if pendingSelection.wallets.isEmpty {
                    WalletSelectionRow(
                        title: "No \(walletTypeLabel) wallets",
                        subtitle: "Create a wallet to continue",
                        leadingText: "0x",
                        isEnabled: false
                    )
                } else {
                    ForEach(pendingSelection.wallets, id: \.id) { wallet in
                        Button {
                            Task { await vm.selectWallet(wallet, from: pendingSelection) }
                        } label: {
                            WalletSelectionRow(
                                title: shortWalletAddress(wallet.address),
                                subtitle: walletSelectionSubtitle(wallet),
                                leadingText: "0x"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isLoading)
                    }
                }
            }
        }
    }

    private var createSection: some View {
        FieldGroup(title: "Create", titleStyle: .secondary) {
            Button {
                Task { await vm.createWallet(from: pendingSelection) }
            } label: {
                WalletSelectionRow(
                    title: "Create New Wallet",
                    subtitle: "\(walletTypeLabel) wallet",
                    leadingText: "+"
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
        }
    }

    private var walletTypeLabel: String {
        pendingSelection.walletType.wireValue
    }

    private func walletSelectionSubtitle(_ wallet: Wallet) -> String {
        [
            nonEmpty(wallet.reference),
            wallet.type.wireValue,
            nonEmpty(wallet.id)
        ]
        .compactMap { $0 }
        .joined(separator: " / ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func shortWalletAddress(_ address: String) -> String {
        guard address.count > 18 else { return address }
        return "\(address.prefix(10))...\(address.suffix(6))"
    }
}

private struct ManualWalletSelectionToggle: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        Toggle(isOn: $vm.useManualWalletSelection) {
            Text("Use manual wallet selection")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WalletSelectionRow: View {
    let title: String
    let subtitle: String
    let leadingText: String
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(leadingText)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(panelBorderColor, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isEnabled {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Wallet Window

struct WalletWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var showSendWindow: Bool = false
    @State private var showCallContractWindow: Bool = false
    @State private var showSignMessageWindow: Bool = false
    @State private var didCopy: Bool = false
    @State private var nativeBalance: String = "—"
    @State private var nativeBalanceRaw: String = ""
    @State private var usdcBalance: String = "—"
    @State private var usdcBalanceRaw: String = ""
    @State private var isFetchingBalance: Bool = false
    @State private var selectedNetwork: Network = Network.polygonAmoy

    private func clearBalance() {
        nativeBalance = "—"
        nativeBalanceRaw = ""
        usdcBalance = "—"
        usdcBalanceRaw = ""
    }

    private func refreshBalance() async {
        guard !vm.oms.wallet.walletAddress.isEmpty else { return }
        isFetchingBalance = true
        clearBalance()
        defer { isFetchingBalance = false }

        do {
            let balances = try await vm.oms.indexer.getTokenBalances(
                network: selectedNetwork,
                contractAddress: usdcContractAddress,
                walletAddress: vm.oms.wallet.walletAddress,
                includeMetadata: false
            )
            if let raw = balances.balances.first?.balance {
                usdcBalance = formatUSDCBalance(raw)
                usdcBalanceRaw = raw
            } else {
                usdcBalance = "0.00"
                usdcBalanceRaw = "0"
            }

            let nativeTokenBalance = try await vm.oms.indexer.getNativeTokenBalance(
                network: selectedNetwork,
                walletAddress: vm.oms.wallet.walletAddress
            )
            if let raw = nativeTokenBalance?.balance {
                nativeBalance = formatNativeTokenBalance(raw)
                nativeBalanceRaw = raw
            } else {
                nativeBalance = "0"
                nativeBalanceRaw = "0"
            }
        } catch {
            clearBalance()
            vm.present(error)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    walletAddressBar
                    walletActions
                    assetSection
                }
                .frame(maxWidth: 560)
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationTitle("My Wallet")
            .appNavigationTitleDisplayMode(.large)
            .task {
                await refreshBalance()
            }
            .onChange(of: selectedNetwork) {
                Task { await refreshBalance() }
            }
            .sheet(isPresented: $showSendWindow) {
                SendTransactionWindow()
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showCallContractWindow) {
                CallContractWindow(onCompleted: {
                    Task { await refreshBalance() }
                })
                .environmentObject(vm)
            }
            .sheet(isPresented: $showSignMessageWindow) {
                SignMessageWindow()
                    .environmentObject(vm)
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
    }

    private var walletAddressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(collapsedAddress(vm.oms.wallet.walletAddress))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button {
                    Clipboard.copy(vm.oms.wallet.walletAddress)
                    didCopy = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(vm.oms.wallet.walletAddress.isEmpty)
                .help(didCopy ? "Copied!" : "Copy address")
            }

            Text(sessionEmail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    private var walletActions: some View {
        HStack(spacing: 0) {
            walletActionButton("Send", systemImage: "arrow.up.circle") {
                showSendWindow = true
            }
            Divider().frame(height: 40)
            walletActionButton("Contract", systemImage: "arrow.up.circle") {
                showCallContractWindow = true
            }
            Divider().frame(height: 40)
            walletActionButton("Sign", systemImage: "signature") {
                showSignMessageWindow = true
            }
            Divider().frame(height: 40)
            walletActionButton("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                vm.signOut()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }

    private var assetSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Assets")
                    .font(.headline)

                Spacer()

                Picker("", selection: $selectedNetwork) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    Task { await refreshBalance() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isFetchingBalance)
                .help("Refresh balance")
            }

            nativeTokenCard
            usdcCard
        }
    }

    private var nativeTokenCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.28, green: 0.54, blue: 0.34))
                    .frame(width: 44, height: 44)

                Image(systemName: "hexagon.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedNetwork.displayName) Native")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(nativeTokenSymbol(for: selectedNetwork))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isFetchingBalance {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(nativeBalance)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(nativeTokenSymbol(for: selectedNetwork))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }

    private var usdcCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.16, green: 0.45, blue: 0.90))
                    .frame(width: 44, height: 44)

                Text("$")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("USD Coin")
                    .font(.subheadline.weight(.semibold))
                Text("USDC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isFetchingBalance {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(usdcBalance)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("$\(usdcBalance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }

    private func collapsedAddress(_ address: String) -> String {
        guard !address.isEmpty else { return "Loading..." }
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private var sessionEmail: String {
        vm.oms.wallet.session.sessionEmail ?? "Email unavailable"
    }

    private func walletActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sign Message Window

struct SignMessageWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var messageText: String = ""
    @State private var network: Network = Network.polygonAmoy
    @State private var signature: String = ""
    @State private var isSigning: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Sign message",
            subtitle: "Create a wallet signature for the selected network.",
            minWidth: 440,
            minHeight: 380
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "Message") {
                TextField("Enter message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                Task {
                    isSigning = true
                    defer { isSigning = false }

                    do {
                        let result = try await vm.oms.wallet.signMessage(
                            network: network,
                            message: messageText
                        )
                        signature = result
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Sign message", systemImage: "signature", loading: isSigning)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(messageText.isEmpty || isSigning)

            if !signature.isEmpty {
                ResultPanel(title: "Signature", text: signature)
            }
        }
        .genericErrorWindow(error: $error)
    }
}

// MARK: - Send Transaction Window

struct SendTransactionWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var toText: String = ""
    @State private var amountText: String = "1000"
    @State private var network: Network = Network.polygonAmoy
    @State private var result: String = ""
    @State private var isSending: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Send transaction",
            subtitle: "Transfer native token value from this wallet.",
            minWidth: 460,
            minHeight: 460
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "To address") {
                TextField("0x...", text: $toText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            FieldGroup(title: "Amount") {
                TextField("Enter amount", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }

            Button {
                Task {
                    isSending = true
                    defer { isSending = false }

                    do {
                        let txResult = try await vm.oms.wallet.sendTransaction(
                            network: network,
                            to: toText,
                            value: amountText,
                            selectFeeOption: .custom { options in
                                try await vm.selectFeeOption(options)
                            }
                        )
                        result = formatTransactionResult(txResult)
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Execute transaction", systemImage: "paperplane", loading: isSending)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(amountText.isEmpty || toText.isEmpty || isSending)

            if !result.isEmpty {
                ResultPanel(title: "Transaction result", text: result)
            }
        }
        .genericErrorWindow(error: $error)
        .sheet(item: $vm.feeOptionSelectionRequest) { request in
            FeeOptionSelectionWindow(request: request)
                .environmentObject(vm)
        }
        .onAppear {
            if toText.isEmpty {
                toText = vm.oms.wallet.walletAddress
            }
        }
    }
}

// MARK: - Call Contract Window

private struct AbiArgInput: Identifiable {
    let id = UUID()
    var type: String = ""
    var value: String = ""
}

/// Convert a free-form text input into a `WebRPCJSONValue`.
///
/// Plain text is always preserved as a `.string` — no numeric coercion. This
/// matters for ABI args because uint256 / int256 values exceed JSON's safe
/// number range and downstream encoders re-interpret them as floats, so the
/// only safe wire format for numbers is a string. JSON literals (`[`, `{`) are
/// still decoded so users can pass tuples / arrays explicitly.
///
/// Rules (in order):
///   - empty → .null
///   - looks like JSON (`[` or `{`) and decodes → .array / .object
///   - otherwise → .string  (numbers, addresses, hex, bools — all kept verbatim)
private func parseAbiValue(_ raw: String) -> WebRPCJSONValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
        return .null
    }

    if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WebRPCJSONValue.self, from: data) {
            return decoded
        }
    }

    return .string(trimmed)
}

struct CallContractWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// Invoked after a successful contract call so the parent view can refresh
    /// any derived state (e.g. balances).
    var onCompleted: (() -> Void)? = nil

    @State private var contractText: String = "0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582"
    @State private var methodText: String = "transfer"
    @State private var network: Network = Network.polygonAmoy
    @State private var args: [AbiArgInput] = [
        AbiArgInput(type: "address", value: "0xE5E8B483FfC05967FcFed58cc98D053265af6D99"),
        AbiArgInput(type: "uint256", value: "1000000"),
    ]
    @State private var result: String = ""
    @State private var isSending: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Call contract",
            subtitle: "Build a contract method call with ABI arguments.",
            minWidth: 500,
            minHeight: 560
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "Contract") {
                TextField("0x...", text: $contractText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            FieldGroup(title: "Method") {
                TextField("e.g. transfer", text: $methodText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            FieldGroup(title: "Arguments") {
                HStack {
                    Spacer()
                    Button {
                        args.append(AbiArgInput())
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Add argument")
                }

                ForEach($args) { $arg in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            abiTypeField(arg: $arg)
                            abiValueField(arg: $arg)
                            removeAbiArgButton(arg: arg)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                abiTypeField(arg: $arg)
                                removeAbiArgButton(arg: arg)
                            }
                            abiValueField(arg: $arg)
                        }
                    }
                }
            }

            Button {
                Task {
                    isSending = true
                    defer { isSending = false }

                    do {
                        let abiArgs: [AbiArg] = args
                            .filter { !$0.type.isEmpty || !$0.value.isEmpty }
                            .map { AbiArg(type: $0.type, value: parseAbiValue($0.value)) }
                        let txResult = try await vm.oms.wallet.callContract(
                            network: network,
                            contract: contractText,
                            method: methodText,
                            args: abiArgs.isEmpty ? nil : abiArgs,
                            selectFeeOption: .custom { options in
                                try await vm.selectFeeOption(options)
                            }
                        )
                        result = formatTransactionResult(txResult)
                        onCompleted?()
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Execute transaction", systemImage: "paperplane", loading: isSending)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(contractText.isEmpty || methodText.isEmpty || isSending)

            if !result.isEmpty {
                ResultPanel(title: "Transaction result", text: result)
            }
        }
        .genericErrorWindow(error: $error)
        .sheet(item: $vm.feeOptionSelectionRequest) { request in
            FeeOptionSelectionWindow(request: request)
                .environmentObject(vm)
        }
    }

    private func abiTypeField(arg: Binding<AbiArgInput>) -> some View {
        TextField("type (e.g. uint256)", text: arg.type)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private func abiValueField(arg: Binding<AbiArgInput>) -> some View {
        TextField("value", text: arg.value)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private func removeAbiArgButton(arg: AbiArgInput) -> some View {
        Button {
            args.removeAll { $0.id == arg.id }
        } label: {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(args.count <= 1)
        .help("Remove argument")
    }
}

// MARK: - Fee Option Selection Window

private struct FeeOptionSelectionWindow: View {
    @EnvironmentObject private var vm: AppViewModel

    let request: FeeOptionSelectionRequest

    @State private var selectedIndex: Int?

    private var selectedOption: FeeOptionWithBalance? {
        guard let selectedIndex, request.options.indices.contains(selectedIndex) else {
            return nil
        }
        return request.options[selectedIndex]
    }

    private var firstAvailableIndex: Int? {
        request.options.firstIndex(where: hasEnoughBalance)
    }

    var body: some View {
        ModalContainer(
            title: "Select fee",
            subtitle: "Choose which token to use for this transaction fee.",
            minWidth: 540,
            minHeight: 520
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(request.options.indices, id: \.self) { index in
                    FeeOptionRow(
                        option: request.options[index],
                        isSelected: selectedIndex == index,
                        onSelect: {
                            selectedIndex = index
                        },
                        onConfirm: {
                            select(request.options[index])
                        }
                    )
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    cancel()
                }

                Spacer()

                Button("Select first available") {
                    if let firstAvailableIndex {
                        select(request.options[firstAvailableIndex])
                    }
                }
                .disabled(firstAvailableIndex == nil)

                Button("Select fee") {
                    if let selectedOption {
                        select(selectedOption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption == nil)
            }
        }
        .onAppear {
            selectedIndex = firstAvailableIndex ?? request.options.indices.first
        }
        .onDisappear {
            if !request.isResolved {
                request.cancel()
            }
            vm.clearFeeOptionSelectionRequest(request)
        }
    }

    private func select(_ option: FeeOptionWithBalance) {
        request.select(option)
        vm.clearFeeOptionSelectionRequest(request)
    }

    private func cancel() {
        request.cancel()
        vm.clearFeeOptionSelectionRequest(request)
    }
}

private struct FeeOptionRow: View {
    let option: FeeOptionWithBalance
    let isSelected: Bool
    let onSelect: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(feeTokenLabel(option))
                        .font(.headline)
                        .lineLimit(1)

                    Text(feeAmountLabel(option))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(balanceStatusLabel(option))
                    .font(.caption)
                    .foregroundStyle(balanceStatusColor(option))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Available: \(option.available ?? "unknown")")
                    Text("Raw balance: \(option.availableRaw ?? "unknown")")
                    Text("Raw fee: \(option.feeOption.value)")
                    if let decimals = option.decimals {
                        Text("Decimals: \(decimals)")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Select") {
                onConfirm()
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : panelBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

private func feeTokenLabel(_ option: FeeOptionWithBalance) -> String {
    let token = option.feeOption.token
    let symbol = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    if !symbol.isEmpty {
        return symbol
    }

    let name = token.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty {
        return name
    }

    return token.tokenId ?? "Unknown token"
}

private func feeAmountLabel(_ option: FeeOptionWithBalance) -> String {
    let displayValue = option.feeOption.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return displayValue.isEmpty ? option.feeOption.value : displayValue
}

private func balanceStatusLabel(_ option: FeeOptionWithBalance) -> String {
    guard let comparison = compareBalanceToFee(option) else {
        return "Balance unavailable"
    }
    return comparison == .orderedAscending ? "Insufficient balance" : "Enough balance"
}

private func balanceStatusColor(_ option: FeeOptionWithBalance) -> Color {
    guard let comparison = compareBalanceToFee(option) else {
        return .secondary
    }
    return comparison == .orderedAscending ? .red : .green
}

private func hasEnoughBalance(_ option: FeeOptionWithBalance) -> Bool {
    compareBalanceToFee(option).map { $0 != .orderedAscending } ?? false
}

private func compareBalanceToFee(_ option: FeeOptionWithBalance) -> ComparisonResult? {
    guard let balance = normalizedUnsignedInteger(option.availableRaw),
          let fee = normalizedUnsignedInteger(option.feeOption.value) else {
        return nil
    }

    if balance.count != fee.count {
        return balance.count < fee.count ? .orderedAscending : .orderedDescending
    }

    if balance == fee {
        return .orderedSame
    }

    return balance < fee ? .orderedAscending : .orderedDescending
}

private func normalizedUnsignedInteger(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          trimmed.allSatisfy({ $0.isNumber }) else {
        return nil
    }

    let stripped = trimmed.drop(while: { $0 == "0" })
    return stripped.isEmpty ? "0" : String(stripped)
}

private func formatTransactionResult(_ result: SendTransactionResponse) -> String {
    """
    txnId: \(result.txnId)
    status: \(result.status.wireValue)
    txnHash: \(result.txnHash ?? "nil")
    """
}

// MARK: - Helpers

#if os(iOS)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

private enum AppNavigationTitleDisplayMode {
    case large
    case inline
}

private extension View {
    @ViewBuilder
    func appNavigationTitleDisplayMode(_ displayMode: AppNavigationTitleDisplayMode) -> some View {
        #if os(iOS)
        switch displayMode {
        case .large:
            navigationBarTitleDisplayMode(.large)
        case .inline:
            navigationBarTitleDisplayMode(.inline)
        }
        #else
        self
        #endif
    }
}

private struct AuthWelcomeHeader: View {
    let subtitle: String

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Sequence logo")

            VStack(alignment: .center, spacing: 6) {
                Text("Welcome")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NavigationScreenContainer<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(
        maxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: maxWidth, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackgroundColor.ignoresSafeArea())
        }
        #if os(macOS)
        .frame(minWidth: maxWidth + 80, minHeight: 520)
        #endif
    }
}

private struct ModalContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let minWidth: CGFloat
    let minHeight: CGFloat
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        minWidth: CGFloat,
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationTitle(title)
            .appNavigationTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: minWidth, minHeight: minHeight)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

private struct FieldGroup<Content: View>: View {
    enum TitleStyle: Equatable {
        case primary
        case secondary
    }

    let title: String
    let titleStyle: TitleStyle
    let content: Content

    init(title: String, titleStyle: TitleStyle = .primary, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleStyle = titleStyle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(titleStyle == .secondary ? Color.secondary : Color.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VerificationCodeInput: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    private let length = 6

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { code = normalized($0) }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            TextField("", text: codeBinding)
                .autocorrectionDisabled()
                .focused($isFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityLabel("6-digit code")
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif

            GeometryReader { proxy in
                let spacing: CGFloat = 8
                let availableWidth = proxy.size.width - spacing * CGFloat(length - 1)
                let boxSize = min(52, max(0, availableWidth / CGFloat(length)))

                HStack(spacing: spacing) {
                    ForEach(0..<length, id: \.self) { index in
                        codeBox(at: index, size: boxSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .accessibilityHidden(true)
            }
            .frame(height: 52)
        }
        .onAppear {
            code = normalized(code)
        }
    }

    private func codeBox(at index: Int, size: CGFloat) -> some View {
        let digit = digit(at: index)
        let isActive = isFocused && index == min(code.count, length - 1)

        return Text(digit)
            .font(.title3.monospacedDigit().weight(.semibold))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(panelBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : panelBorderColor, lineWidth: isActive ? 2 : 1)
            )
    }

    private func digit(at index: Int) -> String {
        let characters = Array(code)
        guard characters.indices.contains(index) else { return "" }
        return String(characters[index])
    }

    private func normalized(_ value: String) -> String {
        String(
            value.compactMap { character in
                character.wholeNumberValue.map(String.init)
            }
            .joined()
            .prefix(length)
        )
    }
}

private struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }
}

private struct ResultPanel: View {
    let title: String
    let text: String

    var body: some View {
        Panel {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            CopyableResult(text: text)
        }
    }
}

/// A truncated, monospaced result string with a copy-to-clipboard button.
struct CopyableResult: View {
    let text: String
    @State private var didCopy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.footnote)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Clipboard.copy(text)
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .help(didCopy ? "Copied!" : "Copy")
        }
    }
}

/// Shared button label that swaps text for a spinner while loading.
@ViewBuilder
private func label(for title: String, systemImage: String? = nil, loading: Bool) -> some View {
    Group {
        if loading {
            ProgressView()
                .progressViewStyle(.circular)
        } else if let systemImage {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .frame(maxWidth: .infinity)
        }
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Previews

#Preview("Login") {
    LoginWindow()
        .environmentObject(AppViewModel())
}

#Preview("Confirm Code") {
    ConfirmCodeWindow()
        .environmentObject(AppViewModel())
}

#Preview("Wallet") {
    WalletWindow()
        .environmentObject(AppViewModel())
}

#Preview("Send Transaction") {
    SendTransactionWindow()
        .environmentObject(AppViewModel())
}

#Preview("Call Contract") {
    CallContractWindow()
        .environmentObject(AppViewModel())
}

#Preview("Sign Message") {
    SignMessageWindow()
        .environmentObject(AppViewModel())
}
