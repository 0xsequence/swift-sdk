import SwiftUI
import Combine
import OMS_SDK
#if os(iOS)
import UIKit
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
    Color(.systemBackground)
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

// MARK: - App State

enum AppScreen {
    case login
    case confirmCode
    case wallet
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var screen: AppScreen = .login
    @Published var isLoading: Bool = false
    @Published var error: GenericAppError?
    @Published var oms: OMSClient = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )

    init() {}

    func checkSession() async {
        let hasSession = !oms.wallet.walletAddress.isEmpty
        screen = hasSession ? .wallet : .login
    }

    func signOut() {
        do {
            try oms.wallet.signOut()
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

    // MARK: Confirm Code

    func submitConfirmCode(code: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await oms.wallet.completeEmailAuth(code: code)
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
    }
}

// MARK: - Login Window

struct LoginWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var inputText: String = ""

    var body: some View {
        ScreenContainer(maxWidth: 440) {
            ScreenHeader(
                title: "Sign in",
                subtitle: "Use your email to access your Sequence wallet."
            )

            FieldGroup(title: "Email") {
                TextField("you@example.com", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            Button {
                Task { await vm.submitLogin(input: inputText) }
            } label: {
                label(for: "Continue", systemImage: "arrow.right", loading: vm.isLoading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(inputText.isEmpty || vm.isLoading)
        }
    }
}

// MARK: - Confirm Code Window

struct ConfirmCodeWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var codeText: String = ""

    var body: some View {
        ScreenContainer(maxWidth: 440) {
            ScreenHeader(
                title: "Confirm email",
                subtitle: "Enter the 6-digit code sent to your email."
            )

            FieldGroup(title: "Code") {
                VerificationCodeInput(code: $codeText)
            }

            Button {
                Task { await vm.submitConfirmCode(code: codeText) }
            } label: {
                label(for: "Verify", systemImage: "checkmark", loading: vm.isLoading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(codeText.count != 6 || vm.isLoading)
        }
    }
}

// MARK: - Wallet Window

struct WalletWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var showSendWindow: Bool = false
    @State private var showCallContractWindow: Bool = false
    @State private var showSignMessageWindow: Bool = false
    @State private var didCopy: Bool = false
    @State private var usdcBalance: String = "—"
    @State private var usdcBalanceRaw: String = ""
    @State private var isFetchingBalance: Bool = false
    @State private var selectedNetwork: Network = Network.polygonAmoy

    private func clearBalance() {
        usdcBalance = "—"
        usdcBalanceRaw = ""
    }

    private func refreshBalance() async {
        guard !vm.oms.wallet.walletAddress.isEmpty else { return }
        isFetchingBalance = true
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
        } catch {
            clearBalance()
            vm.present(error)
        }
    }

    var body: some View {
        ScreenContainer(maxWidth: 560, spacing: 20) {
            ScreenHeader(
                title: "Wallet",
                subtitle: "Connected account"
            )

            walletAddressPanel

            walletActions

            FieldGroup(title: "Network") {
                Picker("Network", selection: $selectedNetwork) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Panel {
                HStack {
                    Label("USDC balance", systemImage: "creditcard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isFetchingBalance {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await refreshBalance() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh balance")
                    }
                }

                Text(usdcBalance)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                if !usdcBalanceRaw.isEmpty {
                    Text("\(usdcBalanceRaw) wei")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
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

    private var walletAddressPanel: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wallet address", systemImage: "wallet.pass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(vm.oms.wallet.walletAddress)
                        .font(.callout)
                        .monospaced()
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Clipboard.copy(vm.oms.wallet.walletAddress)
                    didCopy = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(vm.oms.wallet.walletAddress.isEmpty)
                .help(didCopy ? "Copied!" : "Copy address")

                Button {
                    vm.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                .help("Sign out")
            }
        }
    }

    private var walletActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                walletActionButton("Send", systemImage: "arrow.up.right", action: { showSendWindow = true })
                walletActionButton("Call contract", systemImage: "curlybraces", action: { showCallContractWindow = true })
                walletActionButton("Sign", systemImage: "signature", action: { showSignMessageWindow = true })
            }

            VStack(spacing: 10) {
                walletActionButton("Send transaction", systemImage: "arrow.up.right", action: { showSendWindow = true })
                walletActionButton("Call contract", systemImage: "curlybraces", action: { showCallContractWindow = true })
                walletActionButton("Sign message", systemImage: "signature", action: { showSignMessageWindow = true })
            }
        }
    }

    private func walletActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
                            value: amountText
                        )
                        result = txResult
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
                ResultPanel(title: "Transaction hash", text: result)
            }
        }
        .genericErrorWindow(error: $error)
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
                            args: abiArgs.isEmpty ? nil : abiArgs
                        )
                        result = txResult
                        onCompleted?()
                    } catch {
                        self.error = GenericAppError(error)
                    }
                }
            } label: {
                label(for: "Execute transaction", systemImage: "terminal", loading: isSending)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(contractText.isEmpty || methodText.isEmpty || isSending)

            if !result.isEmpty {
                ResultPanel(title: "Transaction hash", text: result)
            }
        }
        .genericErrorWindow(error: $error)
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

// MARK: - Helpers

private struct ScreenContainer<Content: View>: View {
    let maxWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        maxWidth: CGFloat,
        spacing: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(appBackgroundColor)
        #if os(macOS)
        .frame(minWidth: maxWidth + 80, minHeight: 520)
        #endif
    }
}

private struct ScreenHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)

            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                content
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(appBackgroundColor)
        #if os(macOS)
        .frame(minWidth: minWidth, minHeight: minHeight)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

private struct FieldGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

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
