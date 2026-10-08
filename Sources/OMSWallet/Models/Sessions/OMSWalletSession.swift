import Foundation

/// Expiry and auth metadata for the active wallet session. `WalletClient.session` is non-`nil`
/// exactly when `WalletClient.activeWallet` is.
public struct OMSWalletSession: Equatable, Sendable {
    /// Expiration time for the active wallet session, as the ISO-8601 timestamp returned by the
    /// wallet API (the same value as `WalletCredential.expiresAt`).
    public let expiresAt: String

    /// Auth metadata for the active wallet session.
    public let auth: OMSWalletSessionAuth

    public init(expiresAt: String, auth: OMSWalletSessionAuth) {
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
    /// The ISO-8601 expiry timestamp of the session that expired.
    public let expiredAt: String

    public init(wallet: Wallet?, session: OMSWalletSession, expiredAt: String) {
        self.wallet = wallet
        self.session = session
        self.expiredAt = expiredAt
    }
}

/// A point-in-time view of a session; `wallet` is `nil` while a wallet selection is pending.
struct WalletSessionSnapshot: Equatable {
    let wallet: Wallet?
    /// The ISO-8601 expiry exactly as stored and reported publicly.
    let expiresAt: String
    /// `expiresAt` parsed, used for expiry checks and scheduling.
    let expiryDate: Date
    let auth: OMSWalletSessionAuth

    /// Returns `nil` when `expiresAt` is not a valid ISO-8601 timestamp.
    init?(wallet: Wallet?, expiresAt: String?, auth: OMSWalletSessionAuth) {
        guard let expiresAt, let expiryDate = OMSWalletSession.parseDate(expiresAt) else {
            return nil
        }
        self.wallet = wallet
        self.expiresAt = expiresAt
        self.expiryDate = expiryDate
        self.auth = auth
    }

    var session: OMSWalletSession {
        OMSWalletSession(expiresAt: expiresAt, auth: auth)
    }
}
