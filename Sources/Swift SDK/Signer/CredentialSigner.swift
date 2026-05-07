@available(macOS 12.0, iOS 15.0, *)
protocol CredentialSigner: Sendable {
    var keyType: KeyType { get }

    func credentialId() throws -> String
    func nextNonce() throws -> String
    func sign(preimage: String) throws -> String
    func hasCredential() -> Bool
    func clear() throws
}
