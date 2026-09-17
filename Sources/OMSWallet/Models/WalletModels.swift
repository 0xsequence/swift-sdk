import Foundation

public enum WalletType: Codable, Equatable, Hashable, Sendable {
    case ethereum
    case solana
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .ethereum:
            return "ethereum"
        case .solana:
            return "solana"
        case .unknown(let value):
            return value
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "ethereum":
            self = .ethereum
        case "solana":
            self = .solana
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

public enum WalletKeyOrigin: Codable, Equatable, Hashable, Sendable {
    case enclave
    case imported
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .enclave:
            return "enclave"
        case .imported:
            return "imported"
        case .unknown(let value):
            return value
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "enclave":
            self = .enclave
        case "imported":
            self = .imported
        default:
            self = .unknown(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = WalletKeyOrigin(wireValue: try container.decode(String.self))
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
    public let keyOrigin: WalletKeyOrigin

    public init(
        id: String,
        type: WalletType,
        address: String,
        reference: String? = nil,
        keyOrigin: WalletKeyOrigin
    ) {
        self.id = id
        self.type = type
        self.address = address
        self.reference = reference
        self.keyOrigin = keyOrigin
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
    public let index: UInt32?

    public init(token: String, index: UInt32? = nil) {
        self.token = token
        self.index = index
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

public struct WalletCredential: Codable, Equatable, Sendable {
    public let credentialId: String
    public let expiresAt: String
    public let isCaller: Bool

    public init(credentialId: String, expiresAt: String, isCaller: Bool) {
        self.credentialId = credentialId
        self.expiresAt = expiresAt
        self.isCaller = isCaller
    }
}

public struct RemoteCredentialMetadata: Codable, Equatable, Sendable {
    public let appUrl: String
    public let appName: String
    public let appLogoUrl: String
    public let custom: [String: String]

    public init(appUrl: String, appName: String, appLogoUrl: String, custom: [String: String]) {
        self.appUrl = appUrl
        self.appName = appName
        self.appLogoUrl = appLogoUrl
        self.custom = custom
    }
}

public enum SmartSessionGrant: Equatable, Sendable {
    case nativeTransfer(to: String, limit: String)
    case erc20Transfer(token: String, to: String? = nil, limit: String, cumulative: Bool? = nil)
}

public enum AccessGrantType: String, Codable, Equatable, Sendable {
    case direct
    case remote
}

public struct RemoteAccessGrant: Equatable, Sendable {
    public let credential: WalletCredential
    public let sessionId: String
    public let metadata: RemoteCredentialMetadata
    public let grants: [SmartSessionGrant]

    public init(
        credential: WalletCredential,
        sessionId: String,
        metadata: RemoteCredentialMetadata,
        grants: [SmartSessionGrant]
    ) {
        self.credential = credential
        self.sessionId = sessionId
        self.metadata = metadata
        self.grants = grants
    }
}

public enum AccessGrant: Equatable, Sendable {
    case direct(WalletCredential)
    case remote(RemoteAccessGrant)

    public var credential: WalletCredential {
        switch self {
        case .direct(let credential): credential
        case .remote(let grant): grant.credential
        }
    }
}

public struct AccessGrantPage: Equatable, Sendable {
    public let grants: [AccessGrant]
    public let page: Page?

    public init(grants: [AccessGrant], page: Page? = nil) {
        self.grants = grants
        self.page = page
    }
}

public struct AuthorizedRemoteAccess: Equatable, Sendable {
    public let walletId: String
    public let sessionId: String
    public let expiresAt: String
}

public struct RemoteAccessSession: Equatable, Sendable {
    public let sessionId: String
    public let walletId: String
    public let signerAddress: String
    public let grants: [SmartSessionGrant]
    public let chainId: Int
    public let expiresAt: String
}

public struct SmartSessionGrantUsage: Equatable, Sendable {
    public let grant: SmartSessionGrant
    public let used: String?
}

public struct TransactionStatusResponse: Codable, Equatable, Sendable {
    public let status: TransactionStatus
    public let txnHash: String?

    public init(status: TransactionStatus, txnHash: String? = nil) {
        self.status = status
        self.txnHash = txnHash
    }
}
