
@available(macOS 12.0, iOS 15.0, *)
protocol CredentialSigner: Sendable {
    var alg: SigningAlgorithm { get }

    func credentialId() throws -> String
    func nextNonce() throws -> String
    func sign(preimage: String) throws -> String
    func hasCredential() throws -> Bool
    func clear() throws
    /// Deletes the key only while it is `credentialId`, for a session that ended on its own: a key
    /// another process or a newer sign-in stored meanwhile is kept.
    func clear(ifCredentialId credentialId: String) throws
    /// The credentials of stored keys this signer will not sign with (a software key on an iOS
    /// device, where session keys belong in the Secure Enclave).
    func unusableKeyCredentialIds() throws -> [String]
    /// Deletes the keys `unusableKeyCredentialIds` reports.
    func deleteUnusableKeys() throws
}

@available(macOS 12.0, iOS 15.0, *)
extension CredentialSigner {
    /// For a signer whose key no other process can replace: compares the key, then clears it.
    func clear(ifCredentialId credentialId: String) throws {
        guard try hasCredential(), try self.credentialId().lowercased() == credentialId.lowercased() else {
            return
        }
        try clear()
    }

    /// For a signer that can use every key it stores.
    func unusableKeyCredentialIds() throws -> [String] {
        []
    }

    func deleteUnusableKeys() throws {}
}
