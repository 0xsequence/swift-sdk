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

// MARK: - Errors

struct GenericAppError: Identifiable {
    let id = UUID()
    let message: String

    init(message: String) {
        self.message = message
    }

    init?(_ error: Error) {
        if error is CancellationError {
            return nil
        }
        self.message = errorMessage(for: error)
    }
}

private func errorMessage(for error: Error) -> String {
    if error is CancellationError {
        return "The operation was cancelled."
    }

    if let error = error as? WebRPCError {
        return errorMessage(for: error)
    }

    if let error = error as? WebRPCTransportError {
        if let underlyingDescription = error.underlyingDescription, !underlyingDescription.isEmpty {
            return "Unable to reach the OMS service. \(underlyingDescription)"
        }
        return "Unable to reach the OMS service. \(error.message)"
    }

    if let error = error as? TransactionError {
        switch error {
        case .noFeeOptionsAvailable:
            return "No fee options are available for this transaction."
        case .missingTransactionHash:
            return "The transaction was submitted, but no transaction hash was returned."
        case .transactionFailed(let status):
            return "The transaction failed with status \(status)."
        case .pollingTimedOut:
            return "The transaction is taking longer than expected. Check the wallet activity and try again."
        }
    }

    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
        return description
    }

    let description = String(describing: error)
    return description.isEmpty
        ? "An unexpected error occurred. Please try again."
        : description
}

private func errorMessage(for error: WebRPCError) -> String {
    switch error.kind {
    case .answerIncorrect:
        return "The verification code is incorrect. Please try again."
    case .challengeExpired:
        return "The verification code expired. Request a new code and try again."
    case .commitmentConsumed:
        return "This verification code has already been used. Request a new code and try again."
    case .tooManyAttempts:
        return "Too many attempts. Please wait a moment before trying again."
    case .unauthorized:
        return "You are not authorized for this action. Please sign in again."
    case .unsupportedNetwork:
        return "The selected network is not supported."
    case .transactionFailed:
        return serviceErrorMessage(error, fallback: "The transaction failed.")
    case .walletProviderError:
        return serviceErrorMessage(error, fallback: "The wallet provider could not complete the request.")
    case .walletNotFound:
        return "Wallet not found. Please sign in again."
    case .invalidRequest, .webrpcBadRequest:
        return serviceErrorMessage(error, fallback: "The request was invalid.")
    case .webrpcBadResponse:
        return "The OMS service returned an unexpected response. Please try again."
    case .webrpcRequestFailed:
        return "The OMS request failed. Please check your connection and try again."
    case .internalError, .databaseError, .dataIntegrityError, .encryptionError, .webrpcInternalError, .webrpcServerPanic:
        return "The OMS service encountered an error. Please try again."
    default:
        return serviceErrorMessage(error, fallback: "An unexpected OMS error occurred.")
    }
}

private func serviceErrorMessage(_ error: WebRPCError, fallback: String) -> String {
    let details = [error.message, error.cause]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0 != "endpoint error" && $0 != "bad response" }

    guard let detail = details.first else {
        return fallback
    }

    return "\(fallback) \(detail)"
}

private extension View {
    func genericErrorWindow(error: Binding<GenericAppError?>) -> some View {
        alert(item: error) { error in
            Alert(
                title: Text("Something went wrong"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
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
        VStack(spacing: 24) {
            Text("Sign In with Email")
                .font(.largeTitle)
                .fontWeight(.bold)

            TextField("Enter Email...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await vm.submitLogin(input: inputText) }
            } label: {
                label(for: "Continue", loading: vm.isLoading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty || vm.isLoading)
        }
        .padding(32)
        .frame(maxWidth: 400)
    }
}

// MARK: - Confirm Code Window

struct ConfirmCodeWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var codeText: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Confirm your Email")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("We sent a code to your device.")
                .foregroundStyle(.secondary)

            TextField("6-digit code", text: $codeText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await vm.submitConfirmCode(code: codeText) }
            } label: {
                label(for: "Verify", loading: vm.isLoading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(codeText.isEmpty || vm.isLoading)
        }
        .padding(32)
        .frame(maxWidth: 400)
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
            vm.present(error)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("My Wallet")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(vm.oms.wallet.walletAddress)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

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

            Spacer().frame(height: 8)

            VStack(spacing: 8) {
                Button {
                    showSendWindow = true
                } label: {
                    Text("Send Transaction")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showCallContractWindow = true
                } label: {
                    Text("Call Contract")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showSignMessageWindow = true
                } label: {
                    Text("Sign Message")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer().frame(height: 8)

            Picker("Network", selection: $selectedNetwork) {
                ForEach(supportedNetworks, id: \.self) { network in
                    Text(network.displayName).tag(network)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            // USDC balance card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("USDC Balance")
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .padding(32)
        .frame(maxWidth: 400)
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
        VStack(spacing: 16) {
            HStack {
                Text("Sign Message")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Network")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Network", selection: $network) {
                ForEach(supportedNetworks, id: \.self) { network in
                    Text(network.displayName).tag(network)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Message")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Enter message...", text: $messageText)
                .textFieldStyle(.roundedBorder)

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
                label(for: "Sign Message", loading: isSigning)
            }
            .buttonStyle(.borderedProminent)
            .disabled(messageText.isEmpty || isSigning)

            if !signature.isEmpty {
                Text(signature)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 360)
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
        VStack(spacing: 16) {
            HStack {
                Text("Send Transaction")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Network")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Network", selection: $network) {
                ForEach(supportedNetworks, id: \.self) { network in
                    Text(network.displayName).tag(network)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("To Address")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("0x...", text: $toText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Text("Amount")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Enter amount...", text: $amountText)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

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
                label(for: "Execute Transaction", loading: isSending)
            }
            .buttonStyle(.borderedProminent)
            .disabled(amountText.isEmpty || toText.isEmpty || isSending)

            if !result.isEmpty {
                CopyableResult(text: result)
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 420)
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
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Call Contract")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Network")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Network", selection: $network) {
                    ForEach(supportedNetworks, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Contract")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("0x...", text: $contractText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                Text("Method")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("e.g. transfer", text: $methodText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Text("Args")
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        args.append(AbiArgInput())
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                ForEach($args) { $arg in
                    HStack(spacing: 8) {
                        TextField("type (e.g. uint256)", text: $arg.type)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        TextField("value", text: $arg.value)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        Button {
                            args.removeAll { $0.id == arg.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(args.count <= 1)
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
                    label(for: "Execute Transaction", loading: isSending)
                }
                .buttonStyle(.borderedProminent)
                .disabled(contractText.isEmpty || methodText.isEmpty || isSending)

                if !result.isEmpty {
                    CopyableResult(text: result)
                }
            }
            .padding(32)
        }
        .frame(minWidth: 460, minHeight: 520)
        .genericErrorWindow(error: $error)
    }
}

// MARK: - Helpers

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
        .padding(.top, 8)
    }
}

/// Shared button label that swaps text for a spinner while loading.
@ViewBuilder
private func label(for title: String, loading: Bool) -> some View {
    Group {
        if loading {
            ProgressView()
                .progressViewStyle(.circular)
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
