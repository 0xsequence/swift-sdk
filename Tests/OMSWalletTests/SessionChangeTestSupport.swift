@testable import OMSWallet

extension OMSWalletSessionChangeEvent {
    /// The change's case, for comparing a sequence of changes.
    var name: String {
        switch self {
        case .signedIn: return "signedIn"
        case .restored: return "restored"
        case .walletChanged: return "walletChanged"
        case .expiryUpdated: return "expiryUpdated"
        case .signedOut: return "signedOut"
        case .expired: return "expired"
        }
    }

    /// The expired session of an `.expired` change.
    var expiredSession: OMSWalletExpiredSession? {
        if case .expired(let expired) = self {
            return expired
        }
        return nil
    }
}
