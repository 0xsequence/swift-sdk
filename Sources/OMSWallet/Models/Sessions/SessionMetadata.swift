struct SessionMetadata {
    let expiresAt: String
    let auth: OMSWalletSessionAuth
    /// From the sign-in that created the session; `nil` when unknown.
    let expiryBounds: SessionExpiryBounds?
}
