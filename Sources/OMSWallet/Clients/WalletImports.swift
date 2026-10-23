import Foundation

private enum WalletImportActivationContext {
    case active(walletId: String, metadata: SessionMetadata, revision: UInt64)
    case pending(session: PendingWalletSelectionSession, revision: UInt64)

    var metadata: SessionMetadata {
        switch self {
        case .active(_, let metadata, _):
            return metadata
        case .pending(let session, _):
            return session.metadata
        }
    }

    var revision: UInt64 {
        switch self {
        case .active(_, _, let revision), .pending(_, let revision):
            return revision
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Imports and activates an Ethereum, Solana, or Tron private key.
    ///
    /// The plaintext key is sealed locally to a recipient key from an attested WaaS enclave and is
    /// never sent over the ordinary WaaS transport.
    @discardableResult
    public func importWallet(
        privateKey: WalletImportPrivateKey,
        reference: String? = nil
    ) async throws -> WalletActivationResult {
        try await runSessionOperation(.walletImportWallet) {
            let context = try await walletImportActivationContext(for: privateKey.walletType)
            try WalletImportValidation.validateReference(reference)
            var plaintext = try WalletImportValidation.plaintext(privateKey)
            defer { plaintext.resetBytes(in: plaintext.indices) }

            let recipient = try await getWalletImportRecipientKeyUnchecked(
                cipherSuite: .p256Sha256Aes256Gcm
            )
            guard let recipientPublicKey = Data(base64Encoded: recipient.publicKey) else {
                throw OMSWalletError(code: .validationError, message: "recipient publicKey must be canonical base64")
            }
            let sealed = try P256HPKE.seal(
                recipientPublicKey: recipientPublicKey,
                plaintext: plaintext
            )
            let wallet = try await requestImportWallet(
                walletType: privateKey.walletType,
                keyMaterial: EncryptedWalletImportKeyMaterial(
                    keyId: recipient.keyId,
                    cipherSuite: recipient.cipherSuite,
                    encapsulatedKey: sealed.encapsulatedKey.base64EncodedString(),
                    ciphertext: sealed.ciphertext.base64EncodedString()
                ),
                reference: reference
            )
            try await requireWalletImportActivationContextStillActive(context)
            return try activateImportedWallet(wallet, context: context)
        }
    }

    /// Fetches an attested recipient key for advanced wallet-import encryption flows.
    public func getWalletImportRecipientKey(
        cipherSuite: WalletImportCipherSuite
    ) async throws -> WalletImportRecipientKey {
        try await runSessionOperation(.walletGetImportRecipientKey) {
            try await requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            let recipient = try await getWalletImportRecipientKeyUnchecked(cipherSuite: cipherSuite)
            try await requireWalletSelectionOrActiveSession()
            return recipient
        }
    }

    /// Imports and activates key material encrypted by the caller for an attested WaaS recipient key.
    @discardableResult
    public func importEncryptedWallet(
        walletType: WalletType,
        keyMaterial: EncryptedWalletImportKeyMaterial,
        reference: String? = nil
    ) async throws -> WalletActivationResult {
        try await runSessionOperation(.walletImportEncryptedWallet) {
            let context = try await walletImportActivationContext(for: walletType)
            try WalletImportValidation.validateReference(reference)
            let wallet = try await requestImportWallet(
                walletType: walletType,
                keyMaterial: keyMaterial,
                reference: reference
            )
            try await requireWalletImportActivationContextStillActive(context)
            return try activateImportedWallet(wallet, context: context)
        }
    }

    private func getWalletImportRecipientKeyUnchecked(
        cipherSuite: WalletImportCipherSuite
    ) async throws -> WalletImportRecipientKey {
        let client = try requireWalletImportClient()
        let response = try await client.getRecipientKey(
            GetRecipientKeyRequest(purpose: .walletImport, suite: cipherSuite.waasValue)
        )
        guard !response.keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OMSWalletError(code: .invalidResponse, message: "Wallet import recipient-key response is incomplete")
        }
        return WalletImportRecipientKey(
            keyId: response.keyId,
            cipherSuite: cipherSuite,
            publicKey: try WalletImportValidation.canonicalBase64(response.publicKey, field: "recipient publicKey")
        )
    }

    private func requestImportWallet(
        walletType: WalletType,
        keyMaterial: EncryptedWalletImportKeyMaterial,
        reference: String?
    ) async throws -> Wallet {
        guard !keyMaterial.keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OMSWalletError(code: .validationError, message: "keyMaterial.keyId is required")
        }
        let encapsulatedKey = try WalletImportValidation.canonicalBase64(
            keyMaterial.encapsulatedKey,
            field: "keyMaterial.encapsulatedKey"
        )
        let ciphertext = try WalletImportValidation.canonicalBase64(
            keyMaterial.ciphertext,
            field: "keyMaterial.ciphertext"
        )
        let client = try requireWalletImportClient()
        let response = try await client.importWallet(
            ImportWalletRequest(
                networkFamily: walletType.waasNetworkFamily,
                format: .privateKey,
                keyMaterial: HPKEPayload(
                    keyId: keyMaterial.keyId,
                    suite: keyMaterial.cipherSuite.waasValue,
                    encapsulatedKey: Data(base64Encoded: encapsulatedKey)!,
                    ciphertext: Data(base64Encoded: ciphertext)!
                ),
                reference: reference
            )
        )
        let wallet = try response.wallet.sdkValue
        guard wallet.type == walletType else {
            throw OMSWalletError(code: .invalidResponse, message: "Imported wallet network family does not match the request")
        }
        return wallet
    }

    private func walletImportActivationContext(
        for walletType: WalletType
    ) async throws -> WalletImportActivationContext {
        if let pending = activePendingWalletSelection {
            try requireActivePendingWalletSelection(pending)
            guard pending.walletType == walletType else {
                throw OMSWalletError(
                    code: .validationError,
                    message: "Pending wallet selection requires a \(pending.walletType.wireValue) wallet"
                )
            }
            return .pending(session: pending, revision: sessionRevisionSnapshot())
        }

        try await requireWalletSelectionOrActiveSession()
        try requireActiveCredential()
        return .active(
            walletId: try await requireActiveWalletId(),
            metadata: try currentSessionMetadata(),
            revision: sessionRevisionSnapshot()
        )
    }

    private func requireWalletImportActivationContextStillActive(
        _ context: WalletImportActivationContext
    ) async throws {
        try requireCurrentSessionRevision(context.revision)
        switch context {
        case .active(let walletId, _, _):
            guard try await requireActiveWalletId() == walletId else {
                throw OMSWalletError(code: .sessionMissing, message: "Active wallet session changed")
            }
        case .pending(let session, _):
            try requireActivePendingWalletSelection(session)
        }
    }

    private func activateImportedWallet(
        _ wallet: Wallet,
        context: WalletImportActivationContext
    ) throws -> WalletActivationResult {
        try createSequenceWallet(
            wallet: wallet,
            sessionMetadata: context.metadata,
            requiredSessionRevision: context.revision
        )
        if case .pending = context {
            activePendingWalletSelection = nil
        }
        return WalletActivationResult(wallet: wallet)
    }

    private func requireWalletImportClient() throws -> WaasClient {
        guard let walletImportClient else {
            throw OMSWalletError(
                code: .validationError,
                message: "Wallet import is unavailable for this WaaS environment"
            )
        }
        return walletImportClient
    }
}
