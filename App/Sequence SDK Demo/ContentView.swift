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

/// Display label → on-chain id passed to the SDK.
private let supportedChains: [(label: String, id: String)] = [
    ("polygon", "137"),
    ("amoy", "80002"),
]

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
    @Published var oms: OMSClient = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )

    init() {}

    func checkSession() async {
        let hasSession = !oms.wallet.walletAddress.isEmpty
        screen = hasSession ? .wallet : .login
    }

    func signOut() {
        oms.wallet.signOut()
        screen = .login
    }

    // MARK: Login

    func submitLogin(input: String) async {
        isLoading = true

        await oms.wallet.startEmailAuth(email: input)

        isLoading = false
        screen = .confirmCode
    }

    // MARK: Confirm Code

    func submitConfirmCode(code: String) async {
        isLoading = true

        await oms.wallet.completeEmailAuth(code: code)

        isLoading = false
        screen = .wallet
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
            }

            Button {
                vm.signOut()
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer().frame(height: 8)

            HStack(spacing: 8) {
                Button {
                    showSendWindow = true
                } label: {
                    Text("Send")
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
        }
        .padding(32)
        .frame(maxWidth: 400)
        .sheet(isPresented: $showSendWindow) {
            SendTransactionWindow()
                .environmentObject(vm)
        }
        .sheet(isPresented: $showCallContractWindow) {
            CallContractWindow()
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
    @State private var chainId: String = "80002"   // amoy
    @State private var signature: String = ""
    @State private var isSigning: Bool = false

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

            Text("Chain")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Chain", selection: $chainId) {
                ForEach(supportedChains, id: \.id) { chain in
                    Text(chain.label).tag(chain.id)
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
                    let result = await vm.oms.wallet.signMessage(
                        network: chainId,
                        message: messageText
                    )
                    signature = result
                    isSigning = false
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
    }
}

// MARK: - Send Transaction Window

struct SendTransactionWindow: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var toText: String = ""
    @State private var amountText: String = "1000"
    @State private var chainId: String = "80002"   // amoy
    @State private var result: String = ""
    @State private var isSending: Bool = false

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

            Text("Amount")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Enter amount...", text: $amountText)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

            Text("To Address")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("0x...", text: $toText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            Text("Chain")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Chain", selection: $chainId) {
                ForEach(supportedChains, id: \.id) { chain in
                    Text(chain.label).tag(chain.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    isSending = true
                    let txResult = try! await vm.oms.wallet.sendTransaction(
                        network: chainId,
                        to: toText,
                        value: amountText
                    )
                    result = txResult
                    isSending = false
                }
            } label: {
                label(for: "Execute Transaction", loading: isSending)
            }
            .buttonStyle(.borderedProminent)
            .disabled(amountText.isEmpty || toText.isEmpty || isSending)

            if !result.isEmpty {
                Text(result)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 420)
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

    @State private var contractText: String = "0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582"
    @State private var methodText: String = "transfer"
    @State private var chainId: String = "80002"   // amoy
    @State private var args: [AbiArgInput] = [
        AbiArgInput(type: "address", value: "0x000"),
        AbiArgInput(type: "uint256", value: "1000"),
    ]
    @State private var result: String = ""
    @State private var isSending: Bool = false

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

                Text("Chain")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Chain", selection: $chainId) {
                    ForEach(supportedChains, id: \.id) { chain in
                        Text(chain.label).tag(chain.id)
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
                        let abiArgs: [AbiArg] = args
                            .filter { !$0.type.isEmpty || !$0.value.isEmpty }
                            .map { AbiArg(type: $0.type, value: parseAbiValue($0.value)) }
                        let txResult = try! await vm.oms.wallet.callContract(
                            network: chainId,
                            contract: contractText,
                            method: methodText,
                            args: abiArgs.isEmpty ? nil : abiArgs
                        )
                        result = txResult
                        isSending = false
                    }
                } label: {
                    label(for: "Execute Transaction", loading: isSending)
                }
                .buttonStyle(.borderedProminent)
                .disabled(contractText.isEmpty || methodText.isEmpty || isSending)

                if !result.isEmpty {
                    Text(result)
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .padding(32)
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

// MARK: - Helpers

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
