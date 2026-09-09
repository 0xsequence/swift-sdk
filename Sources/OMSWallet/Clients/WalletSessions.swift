import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
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
        _sessionRevision += 1
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil
        activePendingWalletSelection = nil
        try? credentialSession.clearSignerKeepingCredentials()
        walletAddress = nil
        walletId = ""
        verifier = ""
        challenge = ""
        pendingEmailAuth = nil
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
        return (sessionExpiredObserversLocked(), event)
    }

    func deliverSessionExpiredNotification(_ notification: SessionExpiredNotification?) {
        guard let notification else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            for registration in notification.observers
            where self.isSessionExpiredObserverRegistered(registration.id) {
                registration.observer(notification.event)
            }
        }
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
        let delayNanoseconds = delay * 1_000_000_000
        let cappedNanoseconds = delayNanoseconds.isFinite
            ? min(delayNanoseconds, Double(UInt64.max - 1))
            : Double(UInt64.max - 1)
        let nanoseconds = UInt64(cappedNanoseconds)
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
                throw OMSWalletError.sessionMissing()
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
        try runOMSWalletOperation(.walletSignOut) {
            _ = try clearSession(clearOidcRedirectAuth: true)
        }
    }

    @discardableResult
    func clearSession(
        clearOidcRedirectAuth: Bool,
        requiredSessionRevision: UInt64? = nil
    ) throws -> Bool {
        let clearState = {
            try self.withSessionLock {
                if let requiredSessionRevision,
                   self._sessionRevision != requiredSessionRevision {
                    return false
                }
                self._sessionRevision += 1
                self.latestSessionExpiredEvent = nil
                self.sessionExpiryTask?.cancel()
                self.sessionExpiryTask = nil
                self.activePendingWalletSelection = nil
                try self.credentialSession.clear()
                self.walletAddress = nil
                self.walletId = ""
                self.verifier = ""
                self.challenge = ""
                self.pendingEmailAuth = nil
                self.sessionExpiresAt = nil
                self.sessionAuth = nil
                self.signedClient = self.signedClientFactory(self.credentialSession.signer)
                return true
            }
        }
        if clearOidcRedirectAuth {
            return try withOIDCRedirectAuthProjectLock {
                let cleared: Bool
                do {
                    cleared = try clearState()
                } catch {
                    throw OMSWalletError.storageError(
                        message: "Wallet session cleanup failed.",
                        underlyingError: error
                    )
                }
                guard cleared else {
                    return false
                }
                do {
                    try oidcRedirectAuthStore.clear()
                } catch {
                    throw OMSWalletError.storageError(
                        message: "OIDC redirect auth state cleanup failed.",
                        underlyingError: error
                    )
                }
                return true
            }
        }
        let cleared: Bool
        do {
            cleared = try clearState()
        } catch {
            throw OMSWalletError.storageError(
                message: "Wallet session cleanup failed.",
                underlyingError: error
            )
        }
        guard cleared else {
            return false
        }
        return true
    }

    /// Returns display metadata for a remote credential before the owner approves access.
    public func inspectRemoteCredential(credentialId: String) async throws -> RemoteCredentialMetadata {
        try await runOMSWalletOperation(.walletInspectRemoteCredential) {
            guard !credentialId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OMSWalletError(code: .validationError, message: "credentialId is required")
            }
            return try await publicClient.inspectCredential(
                InspectCredentialRequest(scope: projectId, credentialId: credentialId)
            ).metadata.sdkValue
        }
    }

    /// Authorizes owner-approved EVM smart-session grants for a remote credential.
    public func authorizeRemoteAccess(
        credentialId: String,
        network: Network,
        grants: [SmartSessionGrant],
        expiresAt: String,
        sessionId: String? = nil
    ) async throws -> AuthorizedRemoteAccess {
        try await runOMSWalletOperation(.walletAuthorizeRemoteAccess) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            guard let walletAddress, Self.isEthereumAddress(walletAddress) else {
                throw OMSWalletError(code: .validationError, message: "An active Ethereum wallet is required")
            }
            try validateSmartSessionGrants(grants)
            let response = try await signedClient.authorizeRemoteAccess(
                AuthorizeRemoteAccessRequest(
                    credentialId: credentialId,
                    walletId: walletId,
                    grants: Grants(entries: grants.map(\.waasValue)),
                    expiry: expiresAt,
                    chainId: network.chainId,
                    sessionId: sessionId
                )
            )
            try requireSameActiveWalletSession(walletId)
            return AuthorizedRemoteAccess(
                walletId: walletId,
                sessionId: response.sessionId,
                expiresAt: response.expiry
            )
        }
    }

    /// Returns all wallet access grants, following WaaS cursors automatically.
    public func listAccess(
        pageSize: UInt32? = nil,
        type: AccessGrantType? = nil
    ) async throws -> [AccessGrant] {
        try await runOMSWalletOperation(.walletListAccess) {
            var grants: [AccessGrant] = []
            for try await response in listAccessPages(pageSize: pageSize, type: type) {
                grants += response.grants
            }
            return grants
        }
    }

    /// Returns credential-access pages for this wallet until WaaS stops returning a cursor.
    public func listAccessPages(pageSize: UInt32? = nil, type: AccessGrantType? = nil) -> ListAccessPages {
        ListAccessPages(client: self, pageSize: pageSize, type: type)
    }

    /// Returns one credential-access page for this wallet.
    public func listAccessPage(
        pageSize: UInt32? = nil,
        cursor: String? = nil,
        type: AccessGrantType? = nil
    ) async throws -> AccessGrantPage {
        try await runOMSWalletOperation(.walletListAccessPage) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let response = try await signedClient.listAccess(
                ListAccessRequest(
                    walletId: walletId,
                    page: accessPage(pageSize: pageSize, cursor: cursor)?.waasValue,
                    type: type?.waasValue
                )
            )
            let grants = response.credentials.compactMap(\.sdkValue)
            guard grants.count == response.credentials.count else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Access response contains an invalid credential")
                )
            }
            return AccessGrantPage(grants: grants, page: response.page?.sdkValue)
        }
    }

    public func getRemoteAccessSession(sessionId: String) async throws -> RemoteAccessSession {
        try await runOMSWalletOperation(.walletGetRemoteAccessSession) {
            guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OMSWalletError(code: .validationError, message: "sessionId is required")
            }
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let response = try await signedClient.getSession(GetSessionRequest(sessionId: sessionId))
            try requireSameActiveWalletSession(walletId)
            guard let session = response.session.sdkValue, session.walletId == walletId else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Session does not belong to the active wallet")
                )
            }
            return session
        }
    }

    public func getRemoteAccessSessionUsage(
        sessionId: String,
        network: Network
    ) async throws -> [SmartSessionGrantUsage] {
        try await runOMSWalletOperation(.walletGetRemoteAccessSessionUsage) {
            guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OMSWalletError(code: .validationError, message: "sessionId is required")
            }
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let response = try await signedClient.getSessionUsage(
                GetSessionUsageRequest(sessionId: sessionId, network: network.chainId)
            )
            try requireSameActiveWalletSession(walletId)
            return try response.entries.map { entry in
                guard let grant = entry.grant.sdkValue,
                      entry.used.map(isCanonicalUnsignedDecimal) ?? true else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Session usage contains an invalid grant")
                    )
                }
                return SmartSessionGrantUsage(grant: grant, used: entry.used)
            }
        }
    }

    public func getIdToken(ttlSeconds: UInt32? = nil, customClaims: [String: JSONValue]? = nil) async throws -> String {
        try await runOMSWalletOperation(.walletGetIdToken) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = GetIDTokenRequest(
                walletId: walletId,
                ttlSeconds: ttlSeconds,
                customClaims: customClaims?.waasValues
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
    /// - Parameter credentialId: The unique identifier of the credential to revoke.
    public func revokeAccess(credentialId: String, sessionId: String? = nil) async throws {
        try await runOMSWalletOperation(.walletRevokeAccess) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = RevokeAccessRequest(
                targetCredentialId: credentialId,
                walletId: walletId,
                sessionId: sessionId
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

    private func requireSameActiveWalletSession(_ expectedWalletId: String) throws {
        guard try requireActiveWalletId() == expectedWalletId else {
            throw OMSWalletError(code: .sessionMissing, message: "Active wallet session changed")
        }
        try requireActiveCredential()
    }

    private func validateSmartSessionGrants(_ grants: [SmartSessionGrant]) throws {
        guard !grants.isEmpty else {
            throw OMSWalletError(code: .validationError, message: "At least one grant is required")
        }
        for grant in grants {
            switch grant {
            case .nativeTransfer(let to, let limit):
                guard isEthereumAddressValue(to), isCanonicalUnsignedDecimal(limit) else {
                    throw OMSWalletError(code: .validationError, message: "Invalid native transfer grant")
                }
            case .erc20Transfer(let token, let to, let limit, _):
                guard isEthereumAddressValue(token),
                      to.map(isEthereumAddressValue) ?? true,
                      isCanonicalUnsignedDecimal(limit) else {
                    throw OMSWalletError(code: .validationError, message: "Invalid ERC-20 transfer grant")
                }
            }
        }
    }
}

private extension AccessGrantType {
    var waasValue: WaasGenerated.CredentialType {
        switch self {
        case .direct: .direct
        case .remote: .remote
        }
    }
}

private func isCanonicalUnsignedDecimal(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return false }
    return value == "0" || !value.hasPrefix("0")
}

private func isEthereumAddressValue(_ value: String) -> Bool {
    value.count == 42
        && value.hasPrefix("0x")
        && value.dropFirst(2).allSatisfy { character in
            character.isASCII && character.isHexDigit
        }
}

@available(macOS 12.0, iOS 15.0, *)
public struct ListAccessPages: AsyncSequence {
    public typealias Element = AccessGrantPage

    private let client: WalletClient
    private let pageSize: UInt32?
    private let type: AccessGrantType?

    fileprivate init(client: WalletClient, pageSize: UInt32?, type: AccessGrantType?) {
        self.client = client
        self.pageSize = pageSize
        self.type = type
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(client: client, pageSize: pageSize, type: type)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let client: WalletClient
        private let pageSize: UInt32?
        private let type: AccessGrantType?
        private var cursor: String?
        private var hasStarted = false

        fileprivate init(client: WalletClient, pageSize: UInt32?, type: AccessGrantType?) {
            self.client = client
            self.pageSize = pageSize
            self.type = type
        }

        public mutating func next() async throws -> AccessGrantPage? {
            try await runOMSWalletOperation(.walletListAccessPages) {
                if hasStarted && cursor == nil {
                    return nil
                }

                let response = try await client.listAccessPage(
                    pageSize: pageSize,
                    cursor: cursor,
                    type: type
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
