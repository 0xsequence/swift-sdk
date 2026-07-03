import Foundation

public enum OMSWalletSessionAuth: Codable, Equatable, Sendable {
    case email(OMSWalletEmailSessionAuth)
    case oidc(OMSWalletOidcSessionAuth)

    public var email: String? {
        switch self {
        case .email(let auth):
            return auth.email
        case .oidc(let auth):
            return auth.email
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "email":
            self = .email(try OMSWalletEmailSessionAuth(from: decoder))
        case "oidc":
            self = .oidc(try OMSWalletOidcSessionAuth(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported session auth type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .email(let auth):
            try auth.encode(to: encoder)
        case .oidc(let auth):
            try auth.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

public struct OMSWalletEmailSessionAuth: Codable, Equatable, Sendable {
    public let email: String?

    public init(email: String?) {
        self.email = email
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("email", forKey: .type)
        try container.encodeIfPresent(email, forKey: .email)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case email
    }
}

public enum OMSWalletOidcSessionAuthFlow: String, Codable, Equatable, Sendable {
    case redirect
    case idToken = "id-token"
}

public struct OMSWalletOidcSessionAuth: Codable, Equatable, Sendable {
    public let flow: OMSWalletOidcSessionAuthFlow
    public let issuer: String
    public let provider: String?
    public let providerLabel: String?
    public let email: String?

    public init(
        flow: OMSWalletOidcSessionAuthFlow,
        issuer: String,
        provider: String? = nil,
        providerLabel: String? = nil,
        email: String? = nil
    ) {
        self.flow = flow
        self.issuer = issuer
        self.provider = provider
        self.providerLabel = providerLabel
        self.email = email
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.flow = try container.decode(OMSWalletOidcSessionAuthFlow.self, forKey: .flow)
        self.issuer = try container.decode(String.self, forKey: .issuer)
        self.provider = try container.decodeIfPresent(String.self, forKey: .provider)
        self.providerLabel = try container.decodeIfPresent(String.self, forKey: .providerLabel)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("oidc", forKey: .type)
        try container.encode(flow, forKey: .flow)
        try container.encode(issuer, forKey: .issuer)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(providerLabel, forKey: .providerLabel)
        try container.encodeIfPresent(email, forKey: .email)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case flow
        case issuer
        case provider
        case providerLabel
        case email
    }
}
