import SwiftUI
import Combine
import Swift_SDK

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
    @Published var sequence: SequenceSdk = SequenceSdk(projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE")

    init() {}

    func checkSession() async {
        let hasSession = !sequence.wallet.walletAddress.isEmpty
        screen = hasSession ? .wallet : .login
    }
    
    func signOut() {
        sequence.wallet.signOut()
        screen = .login
    }

    // MARK: Login

    func submitLogin(input: String) async {
        isLoading = true
        
        await sequence.wallet.signInWithEmail(email: input)
        
        isLoading = false
        screen = .confirmCode
    }

    // MARK: Confirm Code

    func submitConfirmCode(code: String) async {
        isLoading = true
        
        let walletData = await sequence.wallet.confirmEmailSignIn(code: code)
        if (walletData.wallets.count == 0) {
            await sequence.wallet.createWallet()
        } else {
            await sequence.wallet.useWallet(walletType: walletData.wallets[0].type)
        }
        
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
    @State private var messageText: String = ""
    @State private var toText: String = ""
    @State private var amountText: String = ""
    @State private var signature: String = ""  // ← add this

    var body: some View {
        VStack(spacing: 12) {
            Text("My Wallet")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(vm.sequence.wallet.walletAddress)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                vm.signOut()
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Spacer().frame(height: 8)
            
            Text("Sign Message")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("Enter message...", text: $messageText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    let result = await vm.sequence.wallet.signMessage(network: "amoy", message: messageText)
                    signature = result
                }
            } label: {
                Text("Sign Message")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(messageText.isEmpty)
            
            Spacer().frame(height: 8)
            
            Text("Send Transaction")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("Enter to...", text: $toText)
                .textFieldStyle(.roundedBorder)
            
            TextField("Enter value...", text: $amountText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    let result = await vm.sequence.wallet.sendTransaction(network: "amoy", to: toText, value: amountText)
                    signature = result
                }
            } label: {
                Text("Send Transaction")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(amountText.isEmpty || toText.isEmpty)

            if !signature.isEmpty {
                Text(signature)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } 
        }
        .padding(32)
        .frame(maxWidth: 400)
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
}
