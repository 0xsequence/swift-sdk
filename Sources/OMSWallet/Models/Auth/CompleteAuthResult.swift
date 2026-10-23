import Foundation

@available(macOS 12.0, iOS 15.0, *)
public enum CompleteAuthResult: Sendable {
    case walletSelected(
        wallet: Wallet,
        wallets: [Wallet],
        credential: WalletCredential
    )
    case walletSelection(PendingWalletSelection)

    public var credential: WalletCredential {
        switch self {
        case .walletSelected(_, _, let credential):
            return credential
        case .walletSelection(let pendingSelection):
            return pendingSelection.credential
        }
    }

    public var wallet: Wallet? {
        switch self {
        case .walletSelected(let wallet, _, _):
            return wallet
        case .walletSelection:
            return nil
        }
    }
}
