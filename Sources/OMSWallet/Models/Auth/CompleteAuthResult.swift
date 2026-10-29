import Foundation

@available(macOS 12.0, iOS 15.0, *)
public enum CompleteAuthResult: Sendable {
    /// A wallet was activated. `wallets` lists the user's wallets, and `claimableWallets` lists
    /// the wallets preallocated for the user that this sign-in did not claim.
    case walletSelected(
        wallet: Wallet,
        wallets: [Wallet],
        claimableWallets: [Wallet],
        credential: WalletCredential
    )
    case walletSelection(PendingWalletSelection)

    public var credential: WalletCredential {
        switch self {
        case .walletSelected(_, _, _, let credential):
            return credential
        case .walletSelection(let pendingSelection):
            return pendingSelection.credential
        }
    }

    public var wallet: Wallet? {
        switch self {
        case .walletSelected(let wallet, _, _, _):
            return wallet
        case .walletSelection:
            return nil
        }
    }

    /// Wallets preallocated for the user that they can claim with
    /// `WalletClient.claimWallet(walletId:)`: the unclaimed ones after `.walletSelected`, or
    /// `PendingWalletSelection.claimableWallets` for `.walletSelection`.
    public var claimableWallets: [Wallet] {
        switch self {
        case .walletSelected(_, _, let claimableWallets, _):
            return claimableWallets
        case .walletSelection(let pendingSelection):
            return pendingSelection.claimableWallets
        }
    }
}
