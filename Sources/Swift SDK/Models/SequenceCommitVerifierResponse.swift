struct SequenceCommitVerifierResponse: Codable {
    let verifier: String?
    let loginHint: String?
    let challenge: String?
}
