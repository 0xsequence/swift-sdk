import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct WalletActivationResult: Sendable {
    public let wallet: Wallet

    public init(wallet: Wallet) {
        self.wallet = wallet
    }
}
