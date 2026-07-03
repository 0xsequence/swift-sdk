public final class OMSClientIdentity: Sendable {
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
}
