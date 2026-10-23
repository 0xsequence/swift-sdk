import Foundation

/// The result of asking WaaS for the active credential's current (sliding) expiry.
enum CredentialRefreshOutcome: @unchecked Sendable {
    /// The session expiry now matches the server's and lies in the future.
    case refreshed
    /// The server reported the credential gone or expired, or its expiry has already passed; the
    /// session has been ended.
    case ended
    /// The server has no `GetCredential` method, so the local expiry stays authoritative.
    case unsupported
    /// The refresh failed for another reason (for example a network error); the session is kept.
    case unavailable(any Error)
    /// There was no session, or the session changed while the refresh was in flight.
    case superseded
}

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Expiry and auth metadata for the active wallet session. Non-`nil` exactly when
    /// `activeWallet` is.
    public var session: OMSWalletSession? {
        withSessionLock {
            currentSessionLocked()?.session
        }
    }

    func restoreStoredWalletSession(_ storedWallet: WalletCredentialSession.WalletMetadata?) {
        guard let storedWallet else {
            return
        }

        guard let storedSession = WalletSessionSnapshot(
            wallet: storedWallet.wallet,
            expiresAt: storedWallet.expiresAt,
            auth: storedWallet.auth
        ) else {
            // An unreadable expiry is treated as expired; restore() discards the stored session.
            _ = credentialSession.restore()
            return
        }
        guard !isSessionExpired(storedSession) else {
            expireStoredSession(storedSession)
            return
        }
        guard let restoredWallet = credentialSession.restore() else {
            return
        }

        activeWallet = restoredWallet.wallet
        sessionExpiresAt = restoredWallet.expiresAt
        sessionAuth = restoredWallet.auth
        if let snapshot = currentSessionSnapshot() {
            scheduleSessionExpiry(snapshot)
            // The stored expiry may be stale: the server slides it forward with use.
            Task { [weak self] in
                _ = await self?.refreshCredentialExpiry()
            }
        }
    }

    func isSessionExpired(_ session: WalletSessionSnapshot) -> Bool {
        currentDate() >= session.expiryDate
    }

    private func expireStoredSession(_ session: WalletSessionSnapshot) {
        deliverSessionExpiredNotification(
            withSessionLock {
                try? credentialSession.clearSignerKeepingCredentials()
                signedClient = signedClientFactory(credentialSession.signer)
                return makeSessionExpiredNotificationLocked(session)
            }
        )
    }

    func expireSession(_ session: WalletSessionSnapshot) {
        deliverSessionExpiredNotification(
            withSessionLock {
                clearActiveSessionForExpiryLocked()
                return makeSessionExpiredNotificationLocked(session)
            }
        )
    }

    func currentSessionSnapshot() -> WalletSessionSnapshot? {
        withSessionLock {
            currentSessionLocked()
        }
    }

    private func currentSessionLocked() -> WalletSessionSnapshot? {
        guard let activeWallet, let sessionAuth else {
            return nil
        }

        return WalletSessionSnapshot(
            wallet: activeWallet,
            expiresAt: sessionExpiresAt,
            auth: sessionAuth
        )
    }

    func expireCurrentSessionIfNeeded() -> SessionExpiredNotification? {
        withSessionLock {
            guard let currentSession = currentSessionLocked(),
                  isSessionExpired(currentSession) else {
                return nil
            }
            clearActiveSessionForExpiryLocked()
            return makeSessionExpiredNotificationLocked(currentSession)
        }
    }

    private func clearActiveSessionForExpiryLocked() {
        _sessionRevision += 1
        _lastCredentialRefreshAt = nil
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil
        activePendingWalletSelection = nil
        try? credentialSession.clearSignerKeepingCredentials()
        activeWallet = nil
        verifier = ""
        challenge = ""
        pendingEmailAuth = nil
        sessionExpiresAt = nil
        sessionAuth = nil
        signedClient = signedClientFactory(credentialSession.signer)
    }

    private func makeSessionExpiredNotificationLocked(_ session: WalletSessionSnapshot) -> SessionExpiredNotification {
        let event = OMSWalletSessionExpiredEvent(
            wallet: session.wallet,
            session: session.session,
            expiredAt: session.expiresAt
        )
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

    /// Schedules the expiry timer for `session`: at its expiry, or, for `retryAttempt` > 0, after
    /// a backed-off delay to recheck a session whose expiry could not be refreshed.
    func scheduleSessionExpiry(_ session: WalletSessionSnapshot, retryAttempt: Int = 0) {
        let delay = retryAttempt > 0
            ? Self.sessionExpiryRetryDelay(attempt: retryAttempt)
            : max(0, session.expiryDate.timeIntervalSince(currentDate()))
        let delayNanoseconds = delay * 1_000_000_000
        let cappedNanoseconds = delayNanoseconds.isFinite
            ? min(delayNanoseconds, Double(UInt64.max - 1))
            : Double(UInt64.max - 1)
        let nanoseconds = UInt64(cappedNanoseconds)
        let task = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.handleSessionExpiryTimer(session, retryAttempt: retryAttempt)
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

    static func sessionExpiryRetryDelay(attempt: Int) -> TimeInterval {
        let exponent = Double(min(max(attempt - 1, 0), 16))
        return min(sessionExpiryRetryBaseSeconds * pow(2, exponent), sessionExpiryRetryMaxSeconds)
    }

    /// At local expiry, asks the server for the current expiry first: a session the server has
    /// extended is rescheduled, and one it cannot vouch for because it is offline is rechecked
    /// later instead of being ended.
    private func handleSessionExpiryTimer(_ session: WalletSessionSnapshot, retryAttempt: Int) async {
        let isDue = withSessionLock { () -> Bool? in
            guard isCurrentSessionSnapshotLocked(session) else {
                return nil
            }
            return isSessionExpired(session)
        }
        guard let isDue else {
            return
        }
        guard isDue else {
            scheduleSessionExpiry(session)
            return
        }
        switch await refreshCredentialExpiry() {
        case .refreshed, .ended, .superseded:
            return
        case .unsupported:
            expireSessionFromTimer(session)
        case .unavailable:
            scheduleSessionExpiry(session, retryAttempt: retryAttempt + 1)
        }
    }

    private func expireSessionFromTimer(_ session: WalletSessionSnapshot) {
        deliverSessionExpiredNotification(
            withSessionLock { () -> SessionExpiredNotification? in
                guard isCurrentSessionSnapshotLocked(session), isSessionExpired(session) else {
                    return nil
                }
                clearActiveSessionForExpiryLocked()
                return makeSessionExpiredNotificationLocked(session)
            }
        )
    }

    /// Before an operation uses a locally expired session, asks the server whether it extended
    /// the expiry. An extended session continues; an ended session throws `sessionExpired`; an
    /// unreachable server throws its error and keeps the session. Without server support the
    /// caller's local expiry check applies as before.
    func refreshLocallyExpiredSession() async throws {
        guard let session = currentSessionSnapshot(), isSessionExpired(session) else {
            return
        }
        switch await refreshCredentialExpiry() {
        case .refreshed, .unsupported, .superseded:
            return
        case .ended:
            throw OMSWalletError.sessionExpired()
        case .unavailable(let error):
            throw error
        }
    }

    /// Fetches the active credential's current expiry with `getCredential` and applies it to the
    /// session. Concurrent callers for the same session share one request, and a result is
    /// applied only while the session it was requested for is still current.
    func refreshCredentialExpiry() async -> CredentialRefreshOutcome {
        enum Start {
            case task(Task<CredentialRefreshOutcome, Never>)
            case outcome(CredentialRefreshOutcome)
        }
        let start = withSessionLock { () -> Start in
            if let inFlight = _credentialRefresh, inFlight.revision == _sessionRevision {
                return .task(inFlight.task)
            }
            guard !_isCredentialRefreshUnsupported else {
                return .outcome(.unsupported)
            }
            guard currentSessionLocked() != nil else {
                return .outcome(.superseded)
            }
            let id = UUID()
            let revision = _sessionRevision
            let client = signedClient
            let task = Task { [weak self] () -> CredentialRefreshOutcome in
                let outcome: CredentialRefreshOutcome
                do {
                    let response = try await client.getCredential()
                    outcome = self?.applyRefreshedCredentialExpiry(
                        response.credential.expiresAt,
                        revision: revision
                    ) ?? .superseded
                } catch {
                    outcome = self?.handleCredentialRefreshFailure(error, revision: revision) ?? .superseded
                }
                self?.finishCredentialRefresh(id)
                return outcome
            }
            _credentialRefresh = (id, revision, task)
            return .task(task)
        }
        switch start {
        case .task(let task):
            return await task.value
        case .outcome(let outcome):
            return outcome
        }
    }

    private func finishCredentialRefresh(_ id: UUID) {
        withSessionLock {
            if _credentialRefresh?.id == id {
                _credentialRefresh = nil
            }
        }
    }

    private func applyRefreshedCredentialExpiry(
        _ expiresAt: String,
        revision: UInt64
    ) -> CredentialRefreshOutcome {
        guard OMSWalletSession.parseDate(expiresAt) != nil else {
            return .unavailable(
                OMSWalletError(code: .invalidResponse, message: "Credential response has an invalid expiresAt")
            )
        }
        enum Applied {
            case superseded
            case extended(WalletSessionSnapshot)
            case expired(SessionExpiredNotification)
        }
        let applied = withSessionLock { () -> Applied in
            guard _sessionRevision == revision,
                  let wallet = activeWallet,
                  let auth = sessionAuth,
                  let session = WalletSessionSnapshot(wallet: wallet, expiresAt: expiresAt, auth: auth) else {
                return .superseded
            }
            // The in-memory session follows the server even if the keychain write fails; a stale
            // stored expiry only means the next launch refreshes again.
            try? credentialSession.persist(wallet: wallet, expiresAt: expiresAt, auth: auth)
            sessionExpiresAt = expiresAt
            _lastCredentialRefreshAt = currentDate()
            guard !isSessionExpired(session) else {
                // The server's expiry has already passed by the local clock; end it as local
                // expiry does rather than refreshing again.
                clearActiveSessionForExpiryLocked()
                return .expired(makeSessionExpiredNotificationLocked(session))
            }
            return .extended(session)
        }
        switch applied {
        case .superseded:
            return .superseded
        case .extended(let session):
            scheduleSessionExpiry(session)
            return .refreshed
        case .expired(let notification):
            deliverSessionExpiredNotification(notification)
            return .ended
        }
    }

    private func handleCredentialRefreshFailure(
        _ error: any Error,
        revision: UInt64
    ) -> CredentialRefreshOutcome {
        if isCredentialRejectedByServer(error) {
            // `SessionCredentialTransport` has normally ended the session already.
            endSessionRejectedByServer(revision: revision)
            return wasSessionRejectedByServer(revision) ? .ended : .superseded
        }
        if let webRPCError = error as? WebRPCError,
           webRPCError.kind == .webrpcBadRoute || webRPCError.error == "WebrpcBadRoute" {
            withSessionLock { _isCredentialRefreshUnsupported = true }
            return .unsupported
        }
        return .unavailable(error)
    }

    /// Starts a background expiry refresh when the last one (or sign-in) is at least
    /// `credentialRefreshIntervalSeconds` old.
    func refreshCredentialExpiryInBackgroundIfStale() {
        let isStale = withSessionLock { () -> Bool in
            guard !_isCredentialRefreshUnsupported, currentSessionLocked() != nil else {
                return false
            }
            guard let lastRefresh = _lastCredentialRefreshAt else {
                return true
            }
            return currentDate().timeIntervalSince(lastRefresh) >= Self.credentialRefreshIntervalSeconds
        }
        guard isStale else {
            return
        }
        Task { [weak self] in
            _ = await self?.refreshCredentialExpiry()
        }
    }

    /// The session revision while a wallet session is active, or `nil` (for example during
    /// sign-in, before a wallet is activated).
    func activeWalletSessionRevision() -> UInt64? {
        withSessionLock { currentSessionLocked() == nil ? nil : _sessionRevision }
    }

    /// Called by `SessionCredentialTransport` for every response to a request signed with the
    /// session credential while `revision` was active.
    func handleSessionCredentialResponse(_ response: WebRPCHTTPResponse, path: String, revision: UInt64) {
        guard (200...299).contains(response.statusCode) else {
            let error = WaasGenerated.decodeWebRPCError(statusCode: response.statusCode, data: response.body)
            if isCredentialRejectedByServer(error) {
                endSessionRejectedByServer(revision: revision)
            }
            return
        }
        if path != WaasAPI.GetCredential.urlPath {
            refreshCredentialExpiryInBackgroundIfStale()
        }
    }

    /// Ends the session as local expiry does when the server reported its credential gone or
    /// expired, unless a newer sign-in or sign-out already replaced it.
    func endSessionRejectedByServer(revision: UInt64) {
        let notification = withSessionLock { () -> SessionExpiredNotification? in
            guard _sessionRevision == revision, let session = currentSessionLocked() else {
                return nil
            }
            clearActiveSessionForExpiryLocked()
            _serverRejectedSessionRevision = revision
            return makeSessionExpiredNotificationLocked(session)
        }
        deliverSessionExpiredNotification(notification)
    }

    func wasSessionRejectedByServer(_ revision: UInt64) -> Bool {
        withSessionLock { _serverRejectedSessionRevision == revision }
    }

    /// Runs an operation that uses the active wallet session's credential. When WaaS rejected that
    /// credential as gone (7202) or expired (7203), `SessionCredentialTransport` has ended the
    /// session, and the operation throws `sessionExpired`.
    func runSessionOperation<T>(
        _ operation: OMSWalletOperation,
        _ body: () async throws -> T
    ) async throws -> T {
        let sessionRevision = activeWalletSessionRevision()
        do {
            return try await runOMSWalletOperation(operation, body)
        } catch let error as OMSWalletError {
            guard let sessionRevision,
                  isCredentialRejectedByServer(error),
                  wasSessionRejectedByServer(sessionRevision) else {
                throw error
            }
            // WaaS rejects the credential before Execute runs, so a rejected Execute sent nothing
            // and is reported as session expired. Status polling after a submitted transaction
            // keeps its txnId; observers still learn that the session ended.
            if error.code == .transactionStatusLookupFailed {
                throw error
            }
            throw OMSWalletError(
                code: .sessionExpired,
                message: OMSWalletError.sessionExpired().localizedDescription,
                operation: operation,
                underlyingError: error
            )
        }
    }

    private func isCurrentSessionSnapshotLocked(_ session: WalletSessionSnapshot) -> Bool {
        guard session.wallet != nil else {
            return false
        }
        return currentSessionLocked() == session
    }

    func reauthenticationSessionEmail() -> String? {
        withSessionLock {
            currentSessionLocked()?.auth.email ?? latestSessionExpiredEvent?.session.auth.email
        }
    }

    func currentSessionMetadata() throws -> SessionMetadata {
        try withSessionLock {
            guard let sessionAuth, let sessionExpiresAt else {
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
    /// and the user will need to sign in again via `startEmailAuth(email:sessionLifetimeSeconds:)`. Navigate to your
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
            do {
                return try self.withSessionLock {
                    if let requiredSessionRevision,
                       self._sessionRevision != requiredSessionRevision {
                        return false
                    }
                    self._sessionRevision += 1
                    self._lastCredentialRefreshAt = nil
                    self.latestSessionExpiredEvent = nil
                    self.sessionExpiryTask?.cancel()
                    self.sessionExpiryTask = nil
                    self.activePendingWalletSelection = nil
                    try self.credentialSession.clear()
                    self.activeWallet = nil
                    self.verifier = ""
                    self.challenge = ""
                    self.pendingEmailAuth = nil
                    self.sessionExpiresAt = nil
                    self.sessionAuth = nil
                    self.signedClient = self.signedClientFactory(self.credentialSession.signer)
                    return true
                }
            } catch {
                throw OMSWalletError.storageError(
                    message: "Wallet session cleanup failed.",
                    underlyingError: error
                )
            }
        }
        guard clearOidcRedirectAuth else {
            return try clearState()
        }
        return try withOIDCRedirectAuthProjectLock {
            guard try clearState() else {
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

    /// Authorizes owner-approved EVM smart-session grants for a remote credential. Omit `sessionId`
    /// to create a session; pass an existing session ID to replace that session's grants and
    /// requested expiry without changing its signer. WaaS caps the effective expiry at the remote
    /// credential's expiry.
    public func authorizeRemoteAccess(
        credentialId: String,
        network: Network,
        grants: [SmartSessionGrant],
        expiresAt: String,
        sessionId: String? = nil
    ) async throws -> AuthorizedRemoteAccess {
        try await runSessionOperation(.walletAuthorizeRemoteAccess) {
            let walletId = try await requireActiveWalletId()
            try requireActiveCredential()
            try await requireActiveWalletType(.ethereum)
            try validateSmartSessionGrants(grants)
            let response = try await signedClient.authorizeRemoteAccess(
                AuthorizeRemoteAccessRequest(
                    credentialId: credentialId,
                    walletId: walletId,
                    grants: Grants(entries: grants.map(\.waasValue)),
                    expiry: expiresAt,
                    chainId: network.waasChainId,
                    sessionId: sessionId
                )
            )
            try await requireSameActiveWalletSession(walletId)
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
        try await runSessionOperation(.walletListAccessPage) {
            let walletId = try await requireActiveWalletId()
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

    /// Returns one owner-visible remote session and verifies that it belongs to the selected wallet.
    public func getRemoteAccessSession(sessionId: String) async throws -> RemoteAccessSession {
        try await runSessionOperation(.walletGetRemoteAccessSession) {
            guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OMSWalletError(code: .validationError, message: "sessionId is required")
            }
            let walletId = try await requireActiveWalletId()
            try requireActiveCredential()
            let response = try await signedClient.getSession(GetSessionRequest(sessionId: sessionId))
            try await requireSameActiveWalletSession(walletId)
            guard let session = response.session.sdkValue, session.walletId == walletId else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Session does not belong to the active wallet")
                )
            }
            return session
        }
    }

    /// Returns the current usage for each bounded grant in an owner-visible remote session.
    public func getRemoteAccessSessionUsage(
        sessionId: String,
        network: Network
    ) async throws -> [SmartSessionGrantUsage] {
        try await runSessionOperation(.walletGetRemoteAccessSessionUsage) {
            guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OMSWalletError(code: .validationError, message: "sessionId is required")
            }
            let walletId = try await requireActiveWalletId()
            try requireActiveCredential()
            let response = try await signedClient.getSessionUsage(
                GetSessionUsageRequest(sessionId: sessionId, network: network.waasChainId)
            )
            try await requireSameActiveWalletSession(walletId)
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
        try await runSessionOperation(.walletGetIdToken) {
            let walletId = try await requireActiveWalletId()
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

    /// Revokes one access grant from the selected wallet. Use `listAccess()` or
    /// `listAccessPage(pageSize:cursor:type:)` first to retrieve the direct or remote grant. Omit
    /// `sessionId` for a direct grant; for a remote grant, pass its session ID to revoke exactly
    /// that session.
    ///
    /// - Parameter credentialId: The unique identifier of the credential to revoke.
    /// - Parameter sessionId: The required session identifier for a remote grant, or `nil` for a
    ///   direct grant.
    public func revokeAccess(credentialId: String, sessionId: String? = nil) async throws {
        try await runSessionOperation(.walletRevokeAccess) {
            let walletId = try await requireActiveWalletId()
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

    private func requireSameActiveWalletSession(_ expectedWalletId: String) async throws {
        guard try await requireActiveWalletId() == expectedWalletId else {
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

/// Whether WaaS rejected the request's credential as not found (7202) or expired (7203).
/// `Unauthorized` (7207) is deliberately excluded: it is not specific to the credential.
func isCredentialRejectedByServer(_ error: any Error) -> Bool {
    let rejectedCodes = [WebRPCErrorKind.keyNotFound.code, WebRPCErrorKind.keyExpired.code]
    if let webRPCError = error as? WebRPCError {
        return rejectedCodes.contains(webRPCError.code)
    }
    guard let upstreamError = (error as? OMSWalletError)?.upstreamError,
          upstreamError.service == .waas,
          let code = upstreamError.code.flatMap(Int.init) else {
        return false
    }
    return rejectedCodes.contains(code)
}
