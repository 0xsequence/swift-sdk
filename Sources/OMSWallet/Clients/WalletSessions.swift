import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Whether there is a persisted OIDC redirect flow that can still be completed by
    /// passing the app callback URL to `handleOidcRedirectCallback`.
    public var canResumeOidcRedirectAuth: Bool {
        (try? oidcRedirectAuthStore.load()) != nil
    }

    /// Snapshot of the current durable wallet-session state.
    public var session: OMSWalletSessionState {
        withSessionLock {
            currentSessionLocked()
        }
    }

    func restoreStoredWalletSession(_ storedWallet: WalletCredentialSession.WalletMetadata?) {
        guard let storedWallet else {
            return
        }

        let storedSession = OMSWalletSessionState(
            walletAddress: storedWallet.walletAddress,
            expiresAtString: storedWallet.expiresAt,
            auth: storedWallet.auth
        )
        guard !isSessionExpired(storedSession) else {
            expireStoredSession(storedSession)
            return
        }
        guard let restoredWallet = credentialSession.restore() else {
            return
        }

        walletId = restoredWallet.walletId
        walletAddress = restoredWallet.walletAddress
        sessionExpiresAt = restoredWallet.expiresAt
        sessionAuth = restoredWallet.auth
        scheduleSessionExpiry(session)
    }

    func isSessionExpired(_ session: OMSWalletSessionState) -> Bool {
        guard let expiresAt = session.expiresAt else {
            return false
        }
        return currentDate() >= expiresAt
    }

    private func expireStoredSession(_ session: OMSWalletSessionState) {
        deliverSessionExpiredNotification(
            withSessionLock {
                try? credentialSession.clearSignerKeepingCredentials()
                signedClient = signedClientFactory(credentialSession.signer)
                return makeSessionExpiredNotificationLocked(session)
            }
        )
    }

    func expireSession(_ session: OMSWalletSessionState) {
        deliverSessionExpiredNotification(
            withSessionLock {
                clearActiveSessionForExpiryLocked()
                return makeSessionExpiredNotificationLocked(session)
            }
        )
    }

    private func currentSessionLocked() -> OMSWalletSessionState {
        guard let walletAddress else {
            return OMSWalletSessionState(walletAddress: nil)
        }

        return OMSWalletSessionState(
            walletAddress: walletAddress,
            expiresAtString: sessionExpiresAt,
            auth: sessionAuth
        )
    }

    func expireCurrentSessionIfNeeded() -> SessionExpiredNotification? {
        withSessionLock {
            let currentSession = currentSessionLocked()
            guard isSessionExpired(currentSession) else {
                return nil
            }
            clearActiveSessionForExpiryLocked()
            return makeSessionExpiredNotificationLocked(currentSession)
        }
    }

    private func clearActiveSessionForExpiryLocked() {
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil
        activePendingWalletSelection = nil
        try? credentialSession.clearSignerKeepingCredentials()
        walletAddress = nil
        walletId = ""
        verifier = ""
        challenge = ""
        sessionExpiresAt = nil
        sessionAuth = nil
        signedClient = signedClientFactory(credentialSession.signer)
    }

    private func makeSessionExpiredNotificationLocked(_ session: OMSWalletSessionState) -> SessionExpiredNotification? {
        guard let expiredAt = session.expiresAt else {
            return nil
        }
        let event = OMSWalletSessionExpiredEvent(session: session, expiredAt: expiredAt)
        latestSessionExpiredEvent = event
        return (onSessionExpired, event)
    }

    func deliverSessionExpiredNotification(_ notification: SessionExpiredNotification?) {
        guard let notification else {
            return
        }
        notification.handler?(notification.event)
    }

    func scheduleSessionExpiry(_ session: OMSWalletSessionState) {
        guard let expiresAt = session.expiresAt else {
            withSessionLock {
                guard isCurrentSessionSnapshotLocked(session) else {
                    return
                }
                sessionExpiryTask?.cancel()
                sessionExpiryTask = nil
            }
            return
        }
        let delay = max(0, expiresAt.timeIntervalSince(currentDate()))
        guard delay > 0 else {
            expireSessionFromTimer(session)
            return
        }
        let nanoseconds = UInt64(min(delay * 1_000_000_000, Double(UInt64.max)))
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.expireSessionFromTimer(session)
        }
        let shouldCancelTask = withSessionLock { () -> Bool in
            guard isCurrentSessionSnapshotLocked(session) else {
                return true
            }
            sessionExpiryTask?.cancel()
            sessionExpiryTask = task
            return false
        }
        if shouldCancelTask {
            task.cancel()
        }
    }

    private func expireSessionFromTimer(_ session: OMSWalletSessionState) {
        let transition = withSessionLock { () -> (
            notification: SessionExpiredNotification?,
            reschedule: OMSWalletSessionState?
        ) in
            guard isCurrentSessionSnapshotLocked(session) else {
                return (nil, nil)
            }
            guard isSessionExpired(session) else {
                return (nil, session)
            }
            clearActiveSessionForExpiryLocked()
            return (makeSessionExpiredNotificationLocked(session), nil)
        }
        if let reschedule = transition.reschedule {
            scheduleSessionExpiry(reschedule)
        }
        deliverSessionExpiredNotification(transition.notification)
    }

    private func isCurrentSessionSnapshotLocked(_ session: OMSWalletSessionState) -> Bool {
        guard let sessionWalletAddress = session.walletAddress else {
            return false
        }
        return walletAddress == sessionWalletAddress
            && OMSWalletSessionState.parseDate(sessionExpiresAt) == session.expiresAt
            && sessionAuth == session.auth
    }

    func reauthenticationSessionEmail() -> String? {
        withSessionLock {
            currentSessionLocked().auth?.email ?? latestSessionExpiredEvent?.session.auth?.email
        }
    }

    func currentSessionMetadata() throws -> SessionMetadata {
        try withSessionLock {
            guard let sessionAuth else {
                throw OmsSdkError.sessionMissing()
            }
            return SessionMetadata(
                expiresAt: sessionExpiresAt,
                auth: sessionAuth
            )
        }
    }

    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, any attempt to restore the session on the next launch will fail
    /// and the user will need to sign in again via `startEmailAuth(email:)`. Navigate to your
    /// sign-in screen after calling this.
    public func signOut() throws {
        try runOmsOperation(.walletSignOut) {
            try clearSession(clearOidcRedirectAuth: true)
        }
    }

    func clearSession(clearOidcRedirectAuth: Bool) throws {
        try withSessionLock {
            latestSessionExpiredEvent = nil
            sessionExpiryTask?.cancel()
            sessionExpiryTask = nil
            activePendingWalletSelection = nil
            try credentialSession.clear()
            walletAddress = nil
            walletId = ""
            verifier = ""
            challenge = ""
            sessionExpiresAt = nil
            sessionAuth = nil
            signedClient = signedClientFactory(credentialSession.signer)
        }
        if clearOidcRedirectAuth {
            try oidcRedirectAuthStore.clear()
        }
    }

    /// Returns a list of credentials that currently have access to this wallet.
    ///
    /// Use this to display active sessions or integrations in your app's account
    /// management UI, or to check what credentials exist before revoking one.
    ///
    /// - Returns: An array of `CredentialInfo` values representing each credential
    ///   with access to this wallet.
    public func listAccess(pageSize: UInt32? = nil) async throws -> [CredentialInfo] {
        try await runOmsOperation(.walletListAccess) {
            var credentials: [CredentialInfo] = []
            for try await response in listAccessPages(pageSize: pageSize) {
                credentials += response.credentials
            }
            return credentials
        }
    }

    /// Returns credential-access pages for this wallet until WaaS stops returning a cursor.
    public func listAccessPages(pageSize: UInt32? = nil) -> ListAccessPages {
        ListAccessPages(client: self, pageSize: pageSize)
    }

    /// Returns one credential-access page for this wallet.
    public func listAccessPage(
        pageSize: UInt32? = nil,
        cursor: String? = nil
    ) async throws -> ListAccessResponse {
        try await runOmsOperation(.walletListAccessPage) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            return try await signedClient.listAccess(
                ListAccessRequest(
                    walletId: walletId,
                    page: accessPage(pageSize: pageSize, cursor: cursor)
                )
            )
        }
    }

    public func getIdToken(ttlSeconds: UInt32? = nil, customClaims: [String: WebRPCJSONValue]? = nil) async throws -> String {
        try await runOmsOperation(.walletGetIdToken) {
            let walletId = try requireActiveWalletId()
            let params = GetIDTokenRequest(
                walletId: walletId,
                ttlSeconds: ttlSeconds,
                customClaims: customClaims
            )

            let response = try await signedClient.getIdToken(params)
            return response.idToken
        }
    }

    /// Revokes access for a specific credential, preventing it from interacting
    /// with this wallet going forward.
    ///
    /// Use `listAccess()` or `listAccessPage(pageSize:cursor:)` first to retrieve
    /// the credential IDs available to revoke.
    /// This action cannot be undone — the credential will need to be re-authorized
    /// to regain access.
    ///
    /// - Parameter targetCredentialId: The unique identifier of the credential to revoke.
    public func revokeAccess(targetCredentialId: String) async throws {
        try await runOmsOperation(.walletRevokeAccess) {
            let walletId = try requireActiveWalletId()
            let params = RevokeAccessRequest(
                targetCredentialId: targetCredentialId,
                walletId: walletId
            )

            _ = try await signedClient.revokeAccess(params)
        }
    }

    private func accessPage(pageSize: UInt32?, cursor: String?) -> Page? {
        if pageSize == nil && cursor == nil {
            return nil
        }

        return Page(limit: pageSize, cursor: cursor)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct ListAccessPages: AsyncSequence {
    public typealias Element = ListAccessResponse

    private let client: WalletClient
    private let pageSize: UInt32?

    fileprivate init(client: WalletClient, pageSize: UInt32?) {
        self.client = client
        self.pageSize = pageSize
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(client: client, pageSize: pageSize)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let client: WalletClient
        private let pageSize: UInt32?
        private var cursor: String?
        private var hasStarted = false

        fileprivate init(client: WalletClient, pageSize: UInt32?) {
            self.client = client
            self.pageSize = pageSize
        }

        public mutating func next() async throws -> ListAccessResponse? {
            try await runOmsOperation(.walletListAccessPages) {
                if hasStarted && cursor == nil {
                    return nil
                }

                let response = try await client.listAccessPage(
                    pageSize: pageSize,
                    cursor: cursor
                )
                hasStarted = true
                cursor = nonEmptyCursor(response.page?.cursor)
                return response
            }
        }

        private func nonEmptyCursor(_ cursor: String?) -> String? {
            guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines), !cursor.isEmpty else {
                return nil
            }
            return cursor
        }
    }
}
