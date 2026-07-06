import Foundation

public enum WalletType: Codable, Equatable, Hashable, Sendable {
    case ethereum
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .ethereum:
            return "ethereum"
        case .unknown(let value):
            return value
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "ethereum":
            self = .ethereum
        default:
            self = .unknown(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = WalletType(wireValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

public struct Wallet: Codable, Equatable, Sendable {
    public let id: String
    public let type: WalletType
    public let address: String
    public let reference: String?

    public init(id: String, type: WalletType, address: String, reference: String? = nil) {
        self.id = id
        self.type = type
        self.address = address
        self.reference = reference
    }
}

public enum TransactionMode: Codable, Equatable, Hashable, Sendable {
    case native
    case relayer
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .native:
            return "native"
        case .relayer:
            return "relayer"
        case .unknown(let value):
            return value
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "native":
            self = .native
        case "relayer":
            self = .relayer
        default:
            self = .unknown(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = TransactionMode(wireValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

public enum TransactionStatus: Codable, Equatable, Hashable, Sendable {
    case quoted
    case pending
    case executed
    case failed
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .quoted:
            return "quoted"
        case .pending:
            return "pending"
        case .executed:
            return "executed"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "quoted":
            self = .quoted
        case "pending":
            self = .pending
        case "executed":
            self = .executed
        case "failed":
            self = .failed
        default:
            self = .unknown(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = TransactionStatus(wireValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

public struct FeeToken: Codable, Equatable, Sendable {
    public let network: String
    public let name: String
    public let symbol: String
    public let type: String
    public let decimals: UInt32?
    public let logoUrl: String?
    public let contractAddress: String?
    public let tokenId: String?

    public init(
        network: String,
        name: String,
        symbol: String,
        type: String,
        decimals: UInt32? = nil,
        logoUrl: String? = nil,
        contractAddress: String? = nil,
        tokenId: String? = nil
    ) {
        self.network = network
        self.name = name
        self.symbol = symbol
        self.type = type
        self.decimals = decimals
        self.logoUrl = logoUrl
        self.contractAddress = contractAddress
        self.tokenId = tokenId
    }

    enum CodingKeys: String, CodingKey {
        case network
        case name
        case symbol
        case type
        case decimals
        case logoUrl = "logoURL"
        case contractAddress
        case tokenId = "tokenID"
    }
}

public struct FeeOption: Codable, Equatable, Sendable {
    public let token: FeeToken
    public let value: String
    public let displayValue: String

    public init(token: FeeToken, value: String, displayValue: String) {
        self.token = token
        self.value = value
        self.displayValue = displayValue
    }
}

public struct FeeOptionSelection: Codable, Equatable, Sendable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct Page: Codable, Equatable, Sendable {
    public let limit: UInt32?
    public let cursor: String?

    public init(limit: UInt32? = nil, cursor: String? = nil) {
        self.limit = limit
        self.cursor = cursor
    }
}

public struct AbiArg: Codable, Equatable, Sendable {
    public let type: String
    public let value: JSONValue

    public init(type: String, value: JSONValue) {
        self.type = type
        self.value = value
    }
}

public struct CredentialInfo: Codable, Equatable, Sendable {
    public let credentialId: String
    public let expiresAt: String
    public let isCaller: Bool

    public init(credentialId: String, expiresAt: String, isCaller: Bool) {
        self.credentialId = credentialId
        self.expiresAt = expiresAt
        self.isCaller = isCaller
    }
}

public struct ListAccessResponse: Codable, Equatable, Sendable {
    public let credentials: [CredentialInfo]
    public let page: Page?

    public init(credentials: [CredentialInfo], page: Page? = nil) {
        self.credentials = credentials
        self.page = page
    }
}

public struct TransactionStatusResponse: Codable, Equatable, Sendable {
    public let status: TransactionStatus
    public let txnHash: String?

    public init(status: TransactionStatus, txnHash: String? = nil) {
        self.status = status
        self.txnHash = txnHash
    }
}
