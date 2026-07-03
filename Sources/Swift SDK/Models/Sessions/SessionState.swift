import Foundation

public struct SessionState: Equatable, Sendable {
    /// Address of the selected wallet in a completed session, or `nil` when the SDK is signed out.
    public let walletAddress: String?

    /// Expiration time for the current completed wallet session, or `nil` when unavailable.
    public let expiresAt: Date?

    /// Auth metadata for the current completed wallet session.
    public let auth: SessionAuth?

    public init(
        walletAddress: String?,
        expiresAt: Date? = nil,
        auth: SessionAuth? = nil
    ) {
        self.walletAddress = walletAddress
        self.expiresAt = expiresAt
        self.auth = auth
    }

    init(
        walletAddress: String?,
        expiresAtString: String?,
        auth: SessionAuth?
    ) {
        self.init(
            walletAddress: walletAddress,
            expiresAt: Self.parseDate(expiresAtString),
            auth: auth
        )
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else {
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

public struct SessionExpiredEvent: Equatable, Sendable {
    public let session: SessionState
    public let expiredAt: Date

    public init(session: SessionState, expiredAt: Date) {
        self.session = session
        self.expiredAt = expiredAt
    }
}
