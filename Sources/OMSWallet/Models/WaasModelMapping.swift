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
        case .solana:
            return .solana
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
        case .solana:
            return .solana
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension WaasGenerated.NetworkFamily {
    var sdkWalletType: WalletType? {
        switch self {
        case .evm:
            return .ethereum
        case .solana:
            return .solana
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension WaasGenerated.KeyOrigin {
    var sdkValue: WalletKeyOrigin? {
        switch self {
        case .enclave:
            return .enclave
        case .imported:
            return .imported
        case .unknown(let value):
            return .unknown(value)
        }
    }
}

extension WalletImportCipherSuite {
    var waasValue: WaasGenerated.Ciphersuite {
        switch self {
        case .x25519Sha256Aes256Gcm: .x25519Sha256Aes256Gcm
        case .x25519Sha256ChaCha20Poly1305: .x25519Sha256ChaCha20Poly1305
        case .p256Sha256Aes256Gcm: .p256Sha256Aes256Gcm
        case .p256Sha256ChaCha20Poly1305: .p256Sha256ChaCha20Poly1305
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
    init(waasValue: WaasGenerated.Wallet) throws {
        guard let type = waasValue.networkFamily?.sdkWalletType else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Wallet response is missing or has an invalid networkFamily"
                )
            )
        }
        guard let keyOrigin = waasValue.keyOrigin?.sdkValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Wallet response is missing or has an invalid keyOrigin"
                )
            )
        }
        self.init(
            id: waasValue.id,
            type: type,
            address: waasValue.address,
            reference: waasValue.reference,
            keyOrigin: keyOrigin
        )
    }
}

extension WaasGenerated.Wallet {
    var sdkValue: Wallet {
        get throws {
            try Wallet(waasValue: self)
        }
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
        WaasGenerated.FeeOptionSelection(token: token, index: index)
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

extension WaasGenerated.CredentialMetadata {
    var sdkValue: RemoteCredentialMetadata {
        RemoteCredentialMetadata(
            appUrl: appUrl,
            appName: appName,
            appLogoUrl: appLogoUrl,
            custom: custom
        )
    }
}

extension SmartSessionGrant {
    var waasValue: WaasGenerated.Grant {
        switch self {
        case .nativeTransfer(let to, let limit):
            return WaasGenerated.Grant(
                kind: .nativeTransfer,
                nativeTransfer: WaasGenerated.NativeTransferGrant(to: to, limit: limit)
            )
        case .erc20Transfer(let token, let to, let limit, let cumulative):
            return WaasGenerated.Grant(
                kind: .erc20transfer,
                erc20transfer: WaasGenerated.ERC20TransferGrant(
                    token: token,
                    to: to,
                    limit: limit,
                    cumulative: cumulative
                )
            )
        }
    }
}

extension WaasGenerated.Grant {
    var sdkValue: SmartSessionGrant? {
        switch kind {
        case .nativeTransfer:
            guard let nativeTransfer,
                  isEthereumAddressValue(nativeTransfer.to),
                  isCanonicalUnsignedDecimal(nativeTransfer.limit) else {
                return nil
            }
            return .nativeTransfer(to: nativeTransfer.to, limit: nativeTransfer.limit)
        case .erc20transfer:
            guard let erc20transfer,
                  isEthereumAddressValue(erc20transfer.token),
                  erc20transfer.to.map(isEthereumAddressValue) ?? true,
                  isCanonicalUnsignedDecimal(erc20transfer.limit) else {
                return nil
            }
            return .erc20Transfer(
                token: erc20transfer.token,
                to: erc20transfer.to,
                limit: erc20transfer.limit,
                cumulative: erc20transfer.cumulative
            )
        case .unknown:
            return nil
        }
    }
}

extension WaasGenerated.CredentialInfo {
    var walletCredential: WalletCredential {
        WalletCredential(
            credentialId: credentialId,
            expiresAt: expiresAt,
            isCaller: isCaller
        )
    }

    var sdkValue: AccessGrant? {
        let credential = walletCredential
        switch type {
        case .direct:
            return .direct(credential)
        case .remote:
            guard let sessionId, !sessionId.isEmpty,
                  let metadata,
                  let entries = grants?.entries,
                  entries.allSatisfy({ $0.sdkValue != nil }) else {
                return nil
            }
            return .remote(
                RemoteAccessGrant(
                    credential: credential,
                    sessionId: sessionId,
                    metadata: metadata.sdkValue,
                    grants: entries.compactMap { $0.sdkValue }
                )
            )
        case .unknown:
            return nil
        }
    }
}

extension WaasGenerated.SessionInfo {
    var sdkValue: RemoteAccessSession? {
        guard let chainId = Int(chainId), chainId > 0, String(chainId) == self.chainId,
              !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !walletId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !expiresAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isEthereumAddressValue(signerAddress),
              grants.entries.allSatisfy({ $0.sdkValue != nil }) else {
            return nil
        }
        return RemoteAccessSession(
            sessionId: sessionId,
            walletId: walletId,
            signerAddress: signerAddress,
            grants: grants.entries.compactMap { $0.sdkValue },
            chainId: chainId,
            expiresAt: expiresAt
        )
    }
}

private func isCanonicalUnsignedDecimal(_ value: String) -> Bool {
    !value.isEmpty
        && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        && (value == "0" || !value.hasPrefix("0"))
}

private func isEthereumAddressValue(_ value: String) -> Bool {
    value.count == 42
        && value.hasPrefix("0x")
        && value.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
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
