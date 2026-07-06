import Foundation
import OMSWalletWaas

extension JSONValue {
    var waasValue: OMSWalletWaas.WebRPCJSONValue {
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

extension OMSWalletWaas.WebRPCJSONValue {
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
    var waasValues: [String: OMSWalletWaas.WebRPCJSONValue] {
        mapValues { $0.waasValue }
    }
}

extension WalletType {
    var waasValue: OMSWalletWaas.WalletType {
        switch self {
        case .ethereum:
            return .ethereum
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension OMSWalletWaas.WalletType {
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
    var waasValue: OMSWalletWaas.TransactionMode {
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

extension OMSWalletWaas.TransactionStatus {
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
    init(waasValue: OMSWalletWaas.Wallet) {
        self.init(
            id: waasValue.id,
            type: waasValue.type.sdkValue,
            address: waasValue.address,
            reference: waasValue.reference
        )
    }
}

extension OMSWalletWaas.Wallet {
    var sdkValue: Wallet {
        Wallet(waasValue: self)
    }
}

extension FeeToken {
    init(waasValue: OMSWalletWaas.FeeToken) {
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

extension OMSWalletWaas.FeeToken {
    var sdkValue: FeeToken {
        FeeToken(waasValue: self)
    }
}

extension FeeOption {
    init(waasValue: OMSWalletWaas.FeeOption) {
        self.init(
            token: waasValue.token.sdkValue,
            value: waasValue.value,
            displayValue: waasValue.displayValue
        )
    }
}

extension OMSWalletWaas.FeeOption {
    var sdkValue: FeeOption {
        FeeOption(waasValue: self)
    }
}

extension FeeOptionSelection {
    var waasValue: OMSWalletWaas.FeeOptionSelection {
        OMSWalletWaas.FeeOptionSelection(token: token)
    }
}

extension Page {
    var waasValue: OMSWalletWaas.Page {
        OMSWalletWaas.Page(limit: limit, cursor: cursor)
    }

    init(waasValue: OMSWalletWaas.Page) {
        self.init(limit: waasValue.limit, cursor: waasValue.cursor)
    }
}

extension OMSWalletWaas.Page {
    var sdkValue: Page {
        Page(waasValue: self)
    }
}

extension AbiArg {
    var waasValue: OMSWalletWaas.AbiArg {
        OMSWalletWaas.AbiArg(type: type, value: value.waasValue)
    }
}

extension CredentialInfo {
    init(waasValue: OMSWalletWaas.CredentialInfo) {
        self.init(
            credentialId: waasValue.credentialId,
            expiresAt: waasValue.expiresAt,
            isCaller: waasValue.isCaller
        )
    }
}

extension OMSWalletWaas.CredentialInfo {
    var sdkValue: CredentialInfo {
        CredentialInfo(waasValue: self)
    }
}

extension ListAccessResponse {
    init(waasValue: OMSWalletWaas.ListAccessResponse) {
        self.init(
            credentials: waasValue.credentials.map { $0.sdkValue },
            page: waasValue.page?.sdkValue
        )
    }
}

extension OMSWalletWaas.ListAccessResponse {
    var sdkValue: ListAccessResponse {
        ListAccessResponse(waasValue: self)
    }
}

extension TransactionStatusResponse {
    init(waasValue: OMSWalletWaas.TransactionStatusResponse) {
        self.init(
            status: waasValue.status.sdkValue,
            txnHash: waasValue.txnHash
        )
    }
}

extension OMSWalletWaas.TransactionStatusResponse {
    var sdkValue: TransactionStatusResponse {
        TransactionStatusResponse(waasValue: self)
    }
}
