import Foundation

extension JSONValue {
    var waasValue: WaasGenerated.WebRPCJSONValue {
        switch self {
        case .object(let value):
            return .object(value.mapValues { $0.waasValue })
        case .array(let value):
            return .array(value.map { $0.waasValue })
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .unsignedInteger(let value):
            return .unsignedInteger(value)
        case .number(let value):
            return .number(value)
        case .bool(let value):
            return .bool(value)
        case .null:
            return .null
        }
    }
}

extension WaasGenerated.WebRPCJSONValue {
    var sdkValue: JSONValue {
        switch self {
        case .object(let value):
            return .object(value.mapValues { $0.sdkValue })
        case .array(let value):
            return .array(value.map { $0.sdkValue })
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .unsignedInteger(let value):
            return .unsignedInteger(value)
        case .number(let value):
            return .number(value)
        case .bool(let value):
            return .bool(value)
        case .null:
            return .null
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    var waasValues: [String: WaasGenerated.WebRPCJSONValue] {
        mapValues { $0.waasValue }
    }
}

extension WalletType {
    var waasValue: WaasGenerated.WalletType {
        switch self {
        case .ethereum:
            return .ethereum
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension WaasGenerated.WalletType {
    var sdkValue: WalletType {
        switch self {
        case .ethereum:
            return .ethereum
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension TransactionMode {
    var waasValue: WaasGenerated.TransactionMode {
        switch self {
        case .native:
            return .native
        case .relayer:
            return .relayer
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension WaasGenerated.TransactionStatus {
    var sdkValue: TransactionStatus {
        switch self {
        case .quoted:
            return .quoted
        case .pending:
            return .pending
        case .executed:
            return .executed
        case .failed:
            return .failed
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension Wallet {
    init(waasValue: WaasGenerated.Wallet) {
        self.init(
            id: waasValue.id,
            type: waasValue.type.sdkValue,
            address: waasValue.address,
            reference: waasValue.reference
        )
    }
}

extension WaasGenerated.Wallet {
    var sdkValue: Wallet {
        Wallet(waasValue: self)
    }
}

extension FeeToken {
    init(waasValue: WaasGenerated.FeeToken) {
        self.init(
            network: waasValue.network,
            name: waasValue.name,
            symbol: waasValue.symbol,
            type: waasValue.type,
            decimals: waasValue.decimals,
            logoUrl: waasValue.logoUrl,
            contractAddress: waasValue.contractAddress,
            tokenId: waasValue.tokenId
        )
    }
}

extension WaasGenerated.FeeToken {
    var sdkValue: FeeToken {
        FeeToken(waasValue: self)
    }
}

extension FeeOption {
    init(waasValue: WaasGenerated.FeeOption) {
        self.init(
            token: waasValue.token.sdkValue,
            value: waasValue.value,
            displayValue: waasValue.displayValue
        )
    }
}

extension WaasGenerated.FeeOption {
    var sdkValue: FeeOption {
        FeeOption(waasValue: self)
    }
}

extension FeeOptionSelection {
    var waasValue: WaasGenerated.FeeOptionSelection {
        WaasGenerated.FeeOptionSelection(token: token)
    }
}

extension Page {
    var waasValue: WaasGenerated.Page {
        WaasGenerated.Page(limit: limit, cursor: cursor)
    }

    init(waasValue: WaasGenerated.Page) {
        self.init(limit: waasValue.limit, cursor: waasValue.cursor)
    }
}

extension WaasGenerated.Page {
    var sdkValue: Page {
        Page(waasValue: self)
    }
}

extension AbiArg {
    var waasValue: WaasGenerated.AbiArg {
        WaasGenerated.AbiArg(type: type, value: value.waasValue)
    }
}

extension CredentialInfo {
    init(waasValue: WaasGenerated.CredentialInfo) {
        self.init(
            credentialId: waasValue.credentialId,
            expiresAt: waasValue.expiresAt,
            isCaller: waasValue.isCaller
        )
    }
}

extension WaasGenerated.CredentialInfo {
    var sdkValue: CredentialInfo {
        CredentialInfo(waasValue: self)
    }
}

extension ListAccessResponse {
    init(waasValue: WaasGenerated.ListAccessResponse) {
        self.init(
            credentials: waasValue.credentials.map { $0.sdkValue },
            page: waasValue.page?.sdkValue
        )
    }
}

extension WaasGenerated.ListAccessResponse {
    var sdkValue: ListAccessResponse {
        ListAccessResponse(waasValue: self)
    }
}

extension TransactionStatusResponse {
    init(waasValue: WaasGenerated.TransactionStatusResponse) {
        self.init(
            status: waasValue.status.sdkValue,
            txnHash: waasValue.txnHash
        )
    }
}

extension WaasGenerated.TransactionStatusResponse {
    var sdkValue: TransactionStatusResponse {
        TransactionStatusResponse(waasValue: self)
    }
}
