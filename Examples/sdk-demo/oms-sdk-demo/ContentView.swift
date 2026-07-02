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

struct SessionExpiredPrompt: Identifiable {
    let id = UUID()
    let event: SessionExpiredEvent

    var email: String? {
        event.session.sessionEmail
    }
}

private enum DemoAuthError: Error, LocalizedError {
    case invalidAuthorizationURL
    case invalidSessionLifetime

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL:
            return "The authorization URL could not be opened."
        case .invalidSessionLifetime:
            return "Enter a session length of at least 1 second."
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
    DesignTokens.Color.page
}

private var panelBackgroundColor: Color {
    DesignTokens.Color.surface
}

private var panelBorderColor: Color {
    DesignTokens.Color.headerBorder
}

private var fieldBackground: some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
        .fill(panelBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
                .stroke(DesignTokens.Color.border, lineWidth: DesignTokens.Stroke.defaultWidth)
        )
}

private extension View {
    func tokenTextInput() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(DesignTokens.Color.primaryText)
            .tint(DesignTokens.Color.info)
            .padding(14)
            .background(fieldBackground)
    }
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
    case introduction
    case login
    case confirmCode
    case walletSelection(PendingWalletSelection)
    case wallet
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var screen: AppScreen = .introduction
    @Published var isLoading: Bool = false
    @Published var error: GenericAppError?
    @Published var safariAuthSession: SafariAuthSession?
    @Published var sessionExpiredPrompt: SessionExpiredPrompt?
    @Published fileprivate var feeOptionSelectionRequest: FeeOptionSelectionRequest?
    @Published var useManualWalletSelection: Bool = false
    @Published var loginEmail: String = ""
    @Published var sessionLifetimeText: String = "604800"
    @Published var oms: OMSClient = try! OMSClient(
        publishableKey: "pk_sdbx_01kqfw9zaykks_01kwetq606fv699qb9bhfmb45s"
    )

    init() {
        oms.wallet.onSessionExpired = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSessionExpired(event)
            }
        }
    }

    private var walletSelectionBehavior: WalletSelectionBehavior {
        useManualWalletSelection ? .manual : .automatic
    }

    var sessionLifetimeSeconds: UInt32? {
        let trimmed = sessionLifetimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = UInt32(trimmed), seconds > 0 else {
            return nil
        }
        return seconds
    }

    func checkSession() async {
        let hasSession = oms.wallet.walletAddress != nil
        screen = hasSession ? .wallet : .introduction
    }

    func signOut() {
        do {
            try oms.wallet.signOut()
            safariAuthSession = nil
            sessionExpiredPrompt = nil
            screen = .introduction
        } catch {
            present(error)
        }
    }

    // MARK: Login

    func submitLogin() async {
        let input = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return
        }
        guard sessionLifetimeSeconds != nil else {
            present(DemoAuthError.invalidSessionLifetime)
            return
        }

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
        guard let lifetimeSeconds = sessionLifetimeSeconds else {
            present(DemoAuthError.invalidSessionLifetime)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let started = try await oms.wallet.startOidcRedirectAuth(
                provider: OidcProviders.google(),
                redirectUri: oidcRedirectUri,
                walletSelection: walletSelectionBehavior,
                sessionLifetimeSeconds: lifetimeSeconds
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
                url.absoluteString
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
        guard let lifetimeSeconds = sessionLifetimeSeconds else {
            present(DemoAuthError.invalidSessionLifetime)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await oms.wallet.completeEmailAuth(
                code: code,
                walletSelection: walletSelectionBehavior,
                sessionLifetimeSeconds: lifetimeSeconds
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

    func retryExpiredSession(_ prompt: SessionExpiredPrompt) async {
        sessionExpiredPrompt = nil

        if let email = prompt.email {
            loginEmail = email
        }

        switch prompt.event.session.loginType {
        case .googleAuth:
            await startGoogleRedirectAuth()
        case .email:
            guard let email = prompt.email else {
                screen = .login
                return
            }
            loginEmail = email
            await submitLogin()
        case .oidc, nil:
            screen = .login
        }
    }

    func dismissExpiredSessionPrompt() {
        sessionExpiredPrompt = nil
        screen = .login
    }

    private func handleSessionExpired(_ event: SessionExpiredEvent) {
        safariAuthSession = nil
        feeOptionSelectionRequest?.cancel()
        feeOptionSelectionRequest = nil
        if let email = event.session.sessionEmail {
            loginEmail = email
        }
        screen = .login
        sessionExpiredPrompt = SessionExpiredPrompt(event: event)
    }

    private func validatedSessionLifetimeSeconds() throws -> UInt32 {
        guard let seconds = sessionLifetimeSeconds else {
            throw DemoAuthError.invalidSessionLifetime
        }
        return seconds
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
            case .introduction:
                IntroductionWindow()
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
        .sessionExpiredAlert(prompt: $vm.sessionExpiredPrompt) { prompt in
            Task {
                await vm.retryExpiredSession(prompt)
            }
        } dismiss: {
            vm.dismissExpiredSessionPrompt()
        }
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

// MARK: - Introduction Window

struct IntroductionWindow: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        NavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 18) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("Sequence logo")

                    VStack(alignment: .center, spacing: 10) {
                        DesignText("OMS SDK demo", variant: .title)
                            .multilineTextAlignment(.center)

                        DesignText("Try wallet authentication, balances, transactions, contract calls, and message signing from one demo wallet.", variant: .body)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 72)

                VStack(alignment: .leading, spacing: 12) {
                    IntroductionFeatureRow(systemImage: "person.crop.circle.badge.checkmark", title: "Authenticate", subtitle: "Start email or Google wallet auth.")
                    IntroductionFeatureRow(systemImage: "creditcard", title: "Review assets", subtitle: "Check native and USDC balances by network.")
                    IntroductionFeatureRow(systemImage: "paperplane", title: "Execute actions", subtitle: "Send value, call contracts, and sign messages.")
                }
                .padding(.top, 40)

                Spacer()

                Button {
                    vm.screen = .login
                } label: {
                    label(for: "Get started", loading: false)
                }
                .buttonStyle(DesignButtonStyle(variant: .primary))
                .padding(.bottom, 24)
            }
        }
    }
}

private struct IntroductionFeatureRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.info)
                .frame(width: 32, height: 32)
                .background(DesignTokens.Color.infoSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.button))

            VStack(alignment: .leading, spacing: 3) {
                DesignText(title, variant: .caption)
                    .font(.custom(DesignTokens.Typography.family, size: 14).weight(.bold))

                DesignText(subtitle, variant: .caption)
            }
        }
    }
}

// MARK: - Login Window

struct LoginWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                AuthWelcomeHeader(
                    title: "Sign in to OMS SDK demo",
                    subtitle: "Sign in to continue to your wallet."
                )
                .padding(.top, 64)

                FieldGroup(title: "Email address", titleStyle: .secondary) {
                    TextField("you@example.com", text: $vm.loginEmail)
                        .tokenTextInput()
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                .padding(.top, 32)

                FieldGroup(title: "Session length", titleStyle: .secondary) {
                    HStack(spacing: 10) {
                        TextField("604800", text: $vm.sessionLifetimeText)
                            .monospacedDigit()
                            .tokenTextInput()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        DesignText("seconds", variant: .caption)
                    }
                }
                .padding(.top, 16)

                ManualWalletSelectionToggle()
                    .padding(.top, 16)

                Spacer()

                Button {
                    Task { await vm.submitLogin() }
                } label: {
                    label(for: "Continue", loading: vm.isLoading)
                }
                .buttonStyle(DesignButtonStyle(variant: .primary))
                .disabled(vm.loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.sessionLifetimeSeconds == nil || vm.isLoading)

                Button {
                    Task { await vm.startGoogleRedirectAuth() }
                } label: {
                    label(for: "Continue with Google", systemImage: "globe", loading: vm.isLoading)
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary))
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

                DesignText("Enter the 6-digit code sent to your email.", variant: .caption)
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
                .buttonStyle(DesignButtonStyle(variant: .primary))
                .disabled(codeText.count != 6 || vm.isLoading)
                .padding(.bottom, 12)

                Button {
                    vm.screen = .login
                    codeText = ""
                } label: {
                    label(for: "Back", loading: false)
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary))
                .disabled(vm.isLoading)
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
                    title: "Select a wallet",
                    subtitle: "Select a wallet to finish signing in."
                )
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    walletsSection
                    createSection

                    if vm.isLoading {
                        ProgressView()
                            .tint(DesignTokens.Color.info)
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
                .buttonStyle(DesignButtonStyle(variant: .secondary))
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
                .foregroundStyle(DesignTokens.Color.primaryText)
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
            .foregroundStyle(DesignTokens.Color.primaryText)
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
        DesignToggle("Use manual wallet selection", isOn: $vm.useManualWalletSelection)
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
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button)
                        .fill(DesignTokens.Color.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button)
                        .stroke(panelBorderColor, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                DesignText(title, variant: .caption)
                    .font(.custom(DesignTokens.Typography.family, size: 14).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                DesignText(subtitle, variant: .caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isEnabled {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
                .stroke(panelBorderColor, lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.input))
    }
}

// MARK: - Wallet Window

struct WalletWindow: View {
    @EnvironmentObject private var vm: AppViewModel
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
        guard let walletAddress = vm.oms.wallet.walletAddress else { return }
        isFetchingBalance = true
        clearBalance()
        defer { isFetchingBalance = false }

        do {
            let balances = try await vm.oms.indexer.getBalances(
                GetBalancesParams(
                    walletAddress: walletAddress,
                    networks: [selectedNetwork],
                    contractAddresses: [usdcContractAddress],
                    includeMetadata: false
                )
            )
            if let raw = balances.balances.first?.balance {
                usdcBalance = formatUSDCBalance(raw)
                usdcBalanceRaw = raw
            } else {
                usdcBalance = "0.00"
                usdcBalanceRaw = "0"
            }

            let nativeTokenBalance = balances.nativeBalances.first {
                $0.chainId == Int64(selectedNetwork.id)
            }
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
        TabView {
            walletTab
                .tabItem {
                    Label("Wallet", systemImage: "wallet.pass")
                }

            SendTransactionWindow(showsCloseButton: false)
                .environmentObject(vm)
                .tabItem {
                    Label("Send", systemImage: "arrow.up.circle")
                }

            CallContractWindow(onCompleted: {
                Task { await refreshBalance() }
            }, showsCloseButton: false)
            .environmentObject(vm)
            .tabItem {
                Label("Call", systemImage: "curlybraces")
            }

            SignMessageWindow(showsCloseButton: false)
                .environmentObject(vm)
                .tabItem {
                    Label("Sign", systemImage: "signature")
                }
        }
        .tint(DesignTokens.Color.info)
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
    }

    private var walletTab: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    walletHeader
                    walletAddressBar
                    assetSection
                }
                .frame(maxWidth: 560)
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .task {
                await refreshBalance()
            }
            .onChange(of: selectedNetwork) { _ in
                Task { await refreshBalance() }
            }
        }
    }

    private var walletHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Wallet")
                .font(.custom(DesignTokens.Typography.family, size: 34).weight(.bold))
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer()

            DesignIconButton(
                systemImage: "rectangle.portrait.and.arrow.right",
                accessibilityLabel: "Sign out"
            ) {
                vm.signOut()
            }
            .help("Sign out")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var walletAddressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(collapsedAddress(vm.oms.wallet.walletAddress ?? ""))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button {
                    guard let walletAddress = vm.oms.wallet.walletAddress else { return }
                    Clipboard.copy(walletAddress)
                    didCopy = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundStyle(didCopy ? DesignTokens.Color.success : DesignTokens.Color.info)
                }
                .buttonStyle(.plain)
                .disabled(vm.oms.wallet.walletAddress == nil)
                .help(didCopy ? "Copied" : "Copy address")
            }

            DesignText(sessionEmail, variant: .caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }

    private var assetSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Assets")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer()

            Picker("", selection: $selectedNetwork) {
                ForEach(supportedNetworks, id: \.self) { network in
                    Text(network.displayName).tag(network)
                }
            }
            .pickerStyle(.menu)
            .tint(DesignTokens.Color.primaryText)
            .foregroundStyle(DesignTokens.Color.primaryText)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            Button {
                Task { await refreshBalance() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(DesignTokens.Color.info)
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
        DesignCard {
            HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Color.success)
                    .frame(width: 44, height: 44)

                Image(systemName: "hexagon.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.primaryButtonText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedNetwork.displayName) Native")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(nativeTokenSymbol(for: selectedNetwork))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isFetchingBalance {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DesignTokens.Color.info)
                } else {
                    Text(nativeBalance)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .monospacedDigit()
                    Text(nativeTokenSymbol(for: selectedNetwork))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .monospacedDigit()
                }
            }
        }
        }
    }

    private var usdcCard: some View {
        DesignCard {
            HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Color.info)
                    .frame(width: 44, height: 44)

                Text("$")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.primaryButtonText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("USD Coin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                Text("USDC")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isFetchingBalance {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DesignTokens.Color.info)
                } else {
                    Text(usdcBalance)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .monospacedDigit()
                    Text("$\(usdcBalance)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .monospacedDigit()
                }
            }
        }
        }
    }

    private func collapsedAddress(_ address: String) -> String {
        guard !address.isEmpty else { return "Loading..." }
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private var sessionEmail: String {
        vm.oms.wallet.session.sessionEmail ?? "Email unavailable"
    }

}

// MARK: - Sign Message Window

struct SignMessageWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    var showsCloseButton: Bool = true

    @State private var messageText: String = ""
    @State private var network: Network = Network.polygonAmoy
    @State private var signature: String = ""
    @State private var isSigning: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Sign message",
            subtitle: "Create a wallet signature for the selected network.",
            showsCloseButton: showsCloseButton
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignTokens.Color.primaryText)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "Message") {
                TextField("Enter message", text: $messageText)
                    .tokenTextInput()
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
            .buttonStyle(DesignButtonStyle(variant: .primary))
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
    var showsCloseButton: Bool = true

    @State private var toText: String = ""
    @State private var amountText: String = "1000"
    @State private var network: Network = Network.polygonAmoy
    @State private var result: SendTransactionResponse?
    @State private var isSending: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Send transaction",
            subtitle: "Transfer native token value from this wallet.",
            showsCloseButton: showsCloseButton
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignTokens.Color.primaryText)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "To address") {
                TextField("0x...", text: $toText)
                    .tokenTextInput()
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            FieldGroup(title: "Amount") {
                TextField("Enter amount", text: $amountText)
                    .tokenTextInput()
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
                        result = txResult
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Execute transaction", systemImage: "paperplane", loading: isSending)
            }
            .buttonStyle(DesignButtonStyle(variant: .primary))
            .disabled(amountText.isEmpty || toText.isEmpty || isSending)

            if let result {
                TransactionResultPanel(result: result)
            }
        }
        .genericErrorWindow(error: $error)
        .sheet(item: $vm.feeOptionSelectionRequest) { request in
            FeeOptionSelectionWindow(request: request)
                .environmentObject(vm)
        }
        .onAppear {
            if toText.isEmpty, let walletAddress = vm.oms.wallet.walletAddress {
                toText = walletAddress
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

    /// Invoked after a successful contract call so the parent view can refresh
    /// any derived state (e.g. balances).
    var onCompleted: (() -> Void)? = nil
    var showsCloseButton: Bool = true

    @State private var contractText: String = "0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582"
    @State private var methodText: String = "transfer"
    @State private var network: Network = Network.polygonAmoy
    @State private var args: [AbiArgInput] = [
        AbiArgInput(type: "address", value: "0xE5E8B483FfC05967FcFed58cc98D053265af6D99"),
        AbiArgInput(type: "uint256", value: "1000000"),
    ]
    @State private var result: SendTransactionResponse?
    @State private var isSending: Bool = false
    @State private var error: GenericAppError?

    var body: some View {
        ModalContainer(
            title: "Call contract",
            subtitle: "Build a contract method call with ABI arguments.",
            showsCloseButton: showsCloseButton
        ) {
            FieldGroup(title: "Network") {
                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignTokens.Color.primaryText)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldGroup(title: "Contract") {
                TextField("0x...", text: $contractText)
                    .tokenTextInput()
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            FieldGroup(title: "Method") {
                TextField("e.g. transfer", text: $methodText)
                    .tokenTextInput()
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
                            .foregroundStyle(DesignTokens.Color.info)
                    }
                    .buttonStyle(.plain)
                    .help("Add argument")
                }

                ForEach($args) { $arg in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            abiTypeField(arg: $arg)
                            removeAbiArgButton(arg: arg)
                        }
                        abiValueField(arg: $arg)
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
                        result = txResult
                        onCompleted?()
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Execute transaction", systemImage: "paperplane", loading: isSending)
            }
            .buttonStyle(DesignButtonStyle(variant: .primary))
            .disabled(contractText.isEmpty || methodText.isEmpty || isSending)

            if let result {
                TransactionResultPanel(result: result)
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
            .tokenTextInput()
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private func abiValueField(arg: Binding<AbiArgInput>) -> some View {
        TextField("value", text: arg.value)
            .tokenTextInput()
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
                .foregroundStyle(DesignTokens.Color.secondaryText)
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
            subtitle: "Choose which token to use for this transaction fee."
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
                .buttonStyle(DesignButtonStyle(variant: .secondary))

                Spacer()

                Button("Select first available") {
                    if let firstAvailableIndex {
                        select(request.options[firstAvailableIndex])
                    }
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary))
                .disabled(firstAvailableIndex == nil)

                Button("Select fee") {
                    if let selectedOption {
                        select(selectedOption)
                    }
                }
                .buttonStyle(DesignButtonStyle(variant: .primary))
                .disabled(selectedOption == nil || selectedOption.map(hasEnoughBalance) == false)
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
                .foregroundStyle(isSelected ? DesignTokens.Color.info : DesignTokens.Color.secondaryText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(feeTokenLabel(option))
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)

                    Text(feeAmountLabel(option))
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                DesignBadge(balanceStatusLabel(option), variant: balanceStatusBadgeVariant(option))
                    .lineLimit(1)

                Text("Available \(option.available ?? "unknown")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Select") {
                onConfirm()
            }
            .buttonStyle(DesignButtonStyle(variant: .secondary))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? DesignTokens.Color.infoSoft : panelBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(isSelected ? DesignTokens.Color.focusRing : panelBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
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

private func balanceStatusBadgeVariant(_ option: FeeOptionWithBalance) -> DesignBadgeVariant {
    guard let comparison = compareBalanceToFee(option) else {
        return .neutral
    }
    return comparison == .orderedAscending ? .danger : .success
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

private struct AuthWelcomeHeader: View {
    var title: String = "Welcome"
    let subtitle: String

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Sequence logo")

            VStack(alignment: .center, spacing: 6) {
                DesignText(title, variant: .title)
                    .multilineTextAlignment(.center)

                DesignText(subtitle, variant: .caption)
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
        NavigationView {
            VStack(spacing: 0) {
                content
            }
                .frame(maxWidth: maxWidth, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .foregroundStyle(DesignTokens.Color.primaryText)
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
    let showsCloseButton: Bool
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsCloseButton: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsCloseButton = showsCloseButton
        self.content = content()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 12) {
                        DesignText(title, variant: .title)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        if showsCloseButton {
                            DesignIconButton(
                                systemImage: "xmark",
                                accessibilityLabel: "Close"
                            ) {
                                dismiss()
                            }
                            .help("Close")
                        }
                    }

                    if let subtitle {
                        DesignText(subtitle, variant: .caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            DesignText(title, variant: titleStyle == .secondary ? .caption : .body)
                .font(titleStyle == .secondary
                    ? Font.custom(DesignTokens.Typography.family, size: 14).weight(.semibold)
                    : Font.custom(DesignTokens.Typography.family, size: 16).weight(.semibold))

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
                .foregroundStyle(DesignTokens.Color.primaryText)
                .tint(DesignTokens.Color.info)
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
            .foregroundStyle(DesignTokens.Color.primaryText)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
                    .fill(panelBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.input)
                    .stroke(isActive ? DesignTokens.Color.focusRing : panelBorderColor, lineWidth: isActive ? 2 : 1)
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
        DesignCard {
            VStack(alignment: .leading, spacing: 12) {
            content
        }
        }
    }
}

private struct ResultPanel: View {
    let title: String
    let text: String

    var body: some View {
        Panel {
            DesignText(title, variant: .body)
                .font(.custom(DesignTokens.Typography.family, size: 16).weight(.semibold))

            CopyableResult(text: text)
        }
    }
}

private struct TransactionResultPanel: View {
    let result: SendTransactionResponse

    var body: some View {
        Panel {
            DesignText("Transaction result", variant: .body)
                .font(.custom(DesignTokens.Typography.family, size: 16).weight(.semibold))

            ResultRow(label: "Status", value: result.status.wireValue)
            ResultRow(label: "Transaction ID", value: result.txnId)

            if let txnHash = result.txnHash, !txnHash.isEmpty {
                ResultRow(label: "Transaction hash", value: txnHash)
            }
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DesignText(label, variant: .caption)
                .font(.custom(DesignTokens.Typography.family, size: 14).weight(.semibold))

            CopyableResult(text: value)
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
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(DesignTokens.Color.secondaryText)
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
                    .foregroundStyle(didCopy ? DesignTokens.Color.success : DesignTokens.Color.info)
            }
            .buttonStyle(DesignButtonStyle(variant: .secondary))
            .help(didCopy ? "Copied" : "Copy")
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
                .tint(DesignTokens.Color.info)
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

private extension View {
    func sessionExpiredAlert(
        prompt: Binding<SessionExpiredPrompt?>,
        retry: @escaping (SessionExpiredPrompt) -> Void,
        dismiss: @escaping () -> Void
    ) -> some View {
        overlay {
            if let prompt = prompt.wrappedValue {
                TokenDialog(
                    title: "Session expired",
                    message: sessionExpiredMessage(prompt),
                    primaryTitle: "Sign in again",
                    primaryAction: {
                        retry(prompt)
                    },
                    secondaryTitle: "Not now",
                    secondaryAction: dismiss
                )
            }
        }
    }
}

private func sessionExpiredMessage(_ prompt: SessionExpiredPrompt) -> String {
    if let email = prompt.email {
        return "Your wallet session expired. Do you want to sign in with \(email) again?"
    }
    return "Your wallet session expired. Do you want to sign in again?"
}

// MARK: - Previews

#Preview("Login") {
    LoginWindow()
        .environmentObject(AppViewModel())
}

#Preview("Introduction") {
    IntroductionWindow()
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
