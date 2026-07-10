import Foundation

@available(macOS 12.0, iOS 15.0, *)
public enum CompleteAuthResult: Sendable {
    case walletSelected(
        walletAddress: String,
        wallet: Wallet,
        wallets: [Wallet],
        credential: CredentialInfo
    )
    case walletSelection(PendingWalletSelection)

    public var credential: CredentialInfo {
        switch self {
        case .walletSelected(_, _, _, let credential):
            return credential
        case .walletSelection(let pendingSelection):
            return pendingSelection.credential
        }
    }

    public var walletAddress: String? {
        switch self {
        case .walletSelected(let walletAddress, _, _, _):
            return walletAddress
        case .walletSelection:
            return nil
        }
    }

    public var wallet: Wallet? {
        switch self {
        case .walletSelected(_, let wallet, _, _):
            return wallet
        case .walletSelection:
            return nil
        }
    }
}
