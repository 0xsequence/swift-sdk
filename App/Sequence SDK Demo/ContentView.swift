import SwiftUI
import Swift_SDK

struct ContentView: View {
    @State private var email: String = ""
    @State private var code: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Sequence Swift SDK")
                .font(.title)
                .fontWeight(.semibold)

            TextField("Enter email...", text: $email)
                .textFieldStyle(.roundedBorder)

            TextField("Enter code...", text: $code)
                .textFieldStyle(.roundedBorder)

            Button("Sign In with Email") {
                Task {
                    await SequenceConnector.shared.SignInWithEmail(email: email)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            Button("Confirm Email Sign In") {
                Task {
                    let response = await SequenceConnector.shared.ConfirmEmailSignIn(code: code)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: 400)
    }
}

#Preview {
    ContentView()
}
