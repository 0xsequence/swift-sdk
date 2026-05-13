/// App-facing identity details returned by wallet authentication.
public final class OMSClientIdentity: Sendable {
    private static let googleIssuer = "https://accounts.google.com"

    public let type: IdentityType
    public let issuer: String?
    public let subject: String

    public init(type: IdentityType, issuer: String? = nil, subject: String) {
        self.type = type
        self.issuer = issuer
        self.subject = subject
    }

    init(_ identity: Identity) {
        self.type = identity.type
        self.issuer = identity.iss
        self.subject = identity.sub
    }

    /// Auth method represented by this identity when it can produce a completed wallet session.
    public var sessionLoginType: SessionLoginType? {
        switch type {
        case .email:
            return .email
        case .oidc:
            return issuer == Self.googleIssuer ? .googleAuth : .oidc
        case .phone, .passkey, .unknown:
            return nil
        }
    }
}
