import Foundation

/// Expiry and auth metadata for the active wallet session. `WalletClient.session` is non-`nil`
/// exactly when `WalletClient.activeWallet` is.
public struct OMSWalletSession: Equatable, Sendable {
    /// Expiration time for the active wallet session.
    public let expiresAt: Date

    /// Auth metadata for the active wallet session.
    public let auth: OMSWalletSessionAuth

    public init(expiresAt: Date, auth: OMSWalletSessionAuth) {
        self.expiresAt = expiresAt
        self.auth = auth
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

public struct OMSWalletSessionExpiredEvent: Equatable, Sendable {
    /// The wallet that was active when the session expired, or `nil` when the credential expired
    /// while a manual wallet selection was still pending.
    public let wallet: Wallet?
    public let session: OMSWalletSession
    public let expiredAt: Date

    public init(wallet: Wallet?, session: OMSWalletSession, expiredAt: Date) {
        self.wallet = wallet
        self.session = session
        self.expiredAt = expiredAt
    }
}

/// A point-in-time view of a session; `wallet` is `nil` while a wallet selection is pending.
struct WalletSessionSnapshot: Equatable {
    let wallet: Wallet?
    let expiresAt: Date
    let auth: OMSWalletSessionAuth

    var session: OMSWalletSession {
        OMSWalletSession(expiresAt: expiresAt, auth: auth)
    }
}
