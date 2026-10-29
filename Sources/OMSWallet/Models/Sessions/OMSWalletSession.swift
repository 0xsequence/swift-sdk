import Foundation

/// Expiry and auth metadata for the active wallet session. `WalletClient.session` is non-`nil`
/// exactly when `WalletClient.activeWallet` is.
public struct OMSWalletSession: Equatable, Sendable {
    /// The current expiry of the active wallet session, as the ISO-8601 timestamp returned by the
    /// wallet API. The server extends it with use up to the requested session lifetime, and the
    /// SDK refreshes it, so it can be later than the sign-in `WalletCredential.expiresAt`.
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

/// A session that expired, as reported by `OMSWalletSessionChangeEvent.expired`.
public struct OMSWalletExpiredSession: Equatable, Sendable {
    /// The wallet that was active when the session expired, or `nil` when the credential expired
    /// while a manual wallet selection was still pending.
    public let wallet: Wallet?
    public let session: OMSWalletSession
    /// The ISO-8601 time the session ended: its expiry, or, when the SDK found it ended before its
    /// expiry (for example after another process's session ended it), the time that was found.
    public let expiredAt: String

    public init(wallet: Wallet?, session: OMSWalletSession, expiredAt: String) {
        self.wallet = wallet
        self.session = session
        self.expiredAt = expiredAt
    }
}

/// A change of `WalletClient.activeWallet` or `WalletClient.session`, with the state right after it.
public enum OMSWalletSessionChangeEvent: Equatable, Sendable {
    /// A sign-in made a wallet active.
    case signedIn(wallet: Wallet, session: OMSWalletSession)
    /// A session saved on this device became active after the client was created, for example once
    /// the device was unlocked after a launch while it was locked. Treat it like `signedIn`; the
    /// user did not just sign in.
    case restored(wallet: Wallet, session: OMSWalletSession)
    /// Another wallet of the same sign-in became active.
    case walletChanged(wallet: Wallet, session: OMSWalletSession)
    /// `session.expiresAt` moved. Safe to ignore unless you show the expiry.
    case expiryUpdated(wallet: Wallet, session: OMSWalletSession)
    /// There is no session any more and it did not expire: `signOut()`, a sign-in started while
    /// signed in, or another process sharing the keychain signing in. Not necessarily the user's
    /// choice.
    case signedOut
    /// The session expired, or the wallet API no longer accepts it.
    case expired(OMSWalletExpiredSession)

    /// The active wallet after the change; `nil` for `signedOut` and `expired`.
    public var activeWallet: Wallet? {
        switch self {
        case .signedIn(let wallet, _), .restored(let wallet, _), .walletChanged(let wallet, _),
             .expiryUpdated(let wallet, _):
            return wallet
        case .signedOut, .expired:
            return nil
        }
    }

    /// The session after the change; non-`nil` exactly when `activeWallet` is.
    public var session: OMSWalletSession? {
        switch self {
        case .signedIn(_, let session), .restored(_, let session), .walletChanged(_, let session),
             .expiryUpdated(_, let session):
            return session
        case .signedOut, .expired:
            return nil
        }
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
