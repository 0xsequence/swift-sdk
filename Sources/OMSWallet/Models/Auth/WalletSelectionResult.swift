import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct WalletSelectionResult: Sendable {
    public let walletAddress: String
    public let wallet: Wallet

    public init(walletAddress: String, wallet: Wallet) {
        self.walletAddress = walletAddress
        self.wallet = wallet
    }
}
