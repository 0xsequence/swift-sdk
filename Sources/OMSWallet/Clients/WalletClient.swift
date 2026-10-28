import Foundation

struct PendingEmailAuth: Sendable {
    let email: String
    let sessionLifetimeSeconds: UInt32
}

@available(macOS 12.0, iOS 15.0, *)
public final class WalletClient: @unchecked Sendable {
    typealias SessionExpiredObserver = @MainActor @Sendable (OMSWalletSessionExpiredEvent) -> Void
    typealias SessionExpiredObserverRegistration = (
        id: UUID,
        observer: SessionExpiredObserver
    )
    typealias SessionExpiredNotification = (
        observers: [SessionExpiredObserverRegistration],
        event: OMSWalletSessionExpiredEvent
    )

    /// The session lifetime used when a sign-in call does not pass `sessionLifetimeSeconds`
    /// (180 days, the maximum).
    public static let defaultSessionLifetimeSeconds: UInt32 = 15_552_000
    /// The largest `sessionLifetimeSeconds` the SDK accepts (180 days).
    public static let maxSessionLifetimeSeconds: UInt32 = 15_552_000

    /// How long after sign-in or the last credential refresh a successful wallet call triggers a
    /// background refresh of the sliding session expiry.
    static let credentialRefreshIntervalSeconds: TimeInterval = 6 * 60 * 60
    /// The first delay before the expiry timer rechecks a session it could not refresh; each retry
    /// doubles it.
    static let sessionExpiryRetryBaseSeconds: TimeInterval = 60
    /// The cap on that retry delay (15 minutes).
    static let sessionExpiryRetryMaxSeconds: TimeInterval = 15 * 60
    /// The longest the expiry timer sleeps at once (about 100 years, well below 2^63 nanoseconds);
    /// a later expiry is checked again when it wakes.
    static let sessionExpiryMaxTimerDelaySeconds: TimeInterval = 100 * 365 * 24 * 60 * 60
    /// How long after a session's predicted server expiry the expiry timer waits before asking WaaS
    /// with `GetCredential`. That request extends a live session itself, so the margin keeps
    /// request latency from letting the check extend an idle one.
    static let sessionExpiryCheckGraceSeconds: TimeInterval = 5 * 60
    /// WaaS skips moving a credential's expiry forward by less than this (its slide dampening).
    /// The expiry timer adds it to its check when the session's `SessionExpiryBounds` are unknown.
    static let serverExpirySlideDampeningSeconds: TimeInterval = 6 * 60 * 60

    static let defaultTransactionStatusPollTimeoutMs: UInt64 = 60_000
    static let defaultFastTransactionStatusPollIntervalMs: UInt64 = 400
    static let defaultFastTransactionStatusPollCount = 5
    static let defaultTransactionStatusPollIntervalMs: UInt64 = 2_000

    private let sessionLock = NSRecursiveLock()
    private var _signedClient: WaasClient
    var signedClient: WaasClient {
        get {
            withSessionLock { _signedClient }
        }
        set {
            withSessionLock { _signedClient = observingSessionCredential(newValue) }
        }
    }
    var publicClient: WaasPublicClient
    private(set) var walletImportClient: WaasClient?
    /// Shared by every client that signs with the session credential, so their nonces stay ordered.
    let signedRequestGate = SignedRequestGate()
    let indexerClient: IndexerClient
    
    let projectId: String
    let environment: OMSWalletEnvironment
    let credentialSession: WalletCredentialSession
    let oidcRedirectAuthStore: any OIDCRedirectAuthStore
    private let oidcRedirectAuthLock: NSRecursiveLock
    let oidcNonceGenerator: () throws -> String
    let signedClientFactory: (any CredentialSigner) -> WaasClient
    let currentDate: () -> Date
    /// Runs the restore read once the app is in the foreground (`ForegroundActivation`).
    let runWhenActive: (@escaping @Sendable () -> Void) -> ForegroundActivation.Cancel
    private var _sessionExpiresAt: String?
    var sessionExpiresAt: String? {
        get {
            withSessionLock { _sessionExpiresAt }
        }
        set {
            withSessionLock { _sessionExpiresAt = newValue }
        }
    }
    private var _sessionAuth: OMSWalletSessionAuth?
    var sessionAuth: OMSWalletSessionAuth? {
        get {
            withSessionLock { _sessionAuth }
        }
        set {
            withSessionLock { _sessionAuth = newValue }
        }
    }
    private var _activePendingWalletSelection: PendingWalletSelectionSession?
    var activePendingWalletSelection: PendingWalletSelectionSession? {
        get {
            withSessionLock { _activePendingWalletSelection }
        }
        set {
            withSessionLock { _activePendingWalletSelection = newValue }
        }
    }
    private var _sessionExpiryTask: Task<Void, Never>?
    var sessionExpiryTask: Task<Void, Never>? {
        get {
            withSessionLock { _sessionExpiryTask }
        }
        set {
            withSessionLock { _sessionExpiryTask = newValue }
        }
    }
    /// Cancels the restore read still waiting for the app to become active.
    var _cancelRestoreRead: ForegroundActivation.Cancel?
    private var _latestSessionExpiredEvent: OMSWalletSessionExpiredEvent?
    var latestSessionExpiredEvent: OMSWalletSessionExpiredEvent? {
        get {
            withSessionLock { _latestSessionExpiredEvent }
        }
        set {
            withSessionLock { _latestSessionExpiredEvent = newValue }
        }
    }
    private var _activeWallet: Wallet?
    var _sessionRevision: UInt64 = 0
    /// The in-flight `getCredential` refresh, shared by concurrent callers of the same session.
    /// `isExpiryCheck` marks the expiry timer's own read, whose send is not recorded as activity.
    var _credentialRefresh: (
        id: UUID,
        revision: UInt64,
        isExpiryCheck: Bool,
        task: Task<CredentialRefreshOutcome, Never>
    )?
    /// Set once the server reports it has no `GetCredential` method; never retried afterwards.
    var _isCredentialRefreshUnsupported = false
    /// When the request that last gave the active session's expiry completed: the sign-in, or the
    /// last successful `GetCredential`. `nil` after a restore until a read succeeds.
    var _lastCredentialRefreshAt: Date?
    /// When the last request signed with the session credential completed, whatever its outcome
    /// (WaaS extends the session for each one that reaches it, at the latest by its completion).
    /// `GetCredential` counts, except the expiry timer's own check, which is sent only after the
    /// bound on the server's expiry. A restore sets it to the restore time, which is after any
    /// request of the previous process.
    var _lastSessionRequestCompletedAt: Date?
    /// When the last `GetCredential` completed; the same timestamp as
    /// `_lastSessionRequestCompletedAt` for that read, so a successful read with no later request
    /// leaves no activity after it.
    var _lastCredentialReadCompletedAt: Date?
    /// The active session's expiry bounds from its sign-in, or `nil` when unknown (a sign-in
    /// whose credential expiry was not after its send).
    var _sessionExpiryBounds: SessionExpiryBounds?
    /// When the scheduled expiry timer fires.
    var _sessionExpiryTimerFireDate: Date?
    /// The last session revision ended because WaaS rejected its credential.
    var _serverRejectedSessionRevision: UInt64?
    private var _sessionExpiredObservers: [UUID: SessionExpiredObserver] = [:]
    private var _verifier = ""
    private var _challenge = ""
    private var _pendingEmailAuth: PendingEmailAuth?

    /// The active wallet, or `nil` until auth completes or a session is restored, while a manual
    /// wallet selection is pending, and after sign-out or session expiry. Same shape as
    /// `listWallets()` entries.
    public internal(set) var activeWallet: Wallet? {
        get {
            withSessionLock { _activeWallet }
        }
        set {
            withSessionLock { _activeWallet = newValue }
        }
    }
    /// The active wallet's ID, or `""` when there is none.
    var walletId: String {
        withSessionLock { _activeWallet?.id ?? "" }
    }
    var verifier: String {
        get {
            withSessionLock { _verifier }
        }
        set {
            withSessionLock { _verifier = newValue }
        }
    }
    var challenge: String {
        get {
            withSessionLock { _challenge }
        }
        set {
            withSessionLock { _challenge = newValue }
        }
    }
    var pendingEmailAuth: PendingEmailAuth? {
        get {
            withSessionLock { _pendingEmailAuth }
        }
        set {
            withSessionLock { _pendingEmailAuth = newValue }
        }
    }

    func saveNewPendingOIDCRedirectAuth(
        _ pending: PendingOIDCRedirectAuth,
        requiredSessionRevision: UInt64
    ) throws {
        try withOIDCRedirectAuthProjectLock {
            try withSessionLock {
                try requireCurrentSessionRevisionLocked(requiredSessionRevision)
                try oidcRedirectAuthStore.save(pending)
            }
        }
    }

    func loadPendingOIDCRedirectAuth() throws -> PendingOIDCRedirectAuth? {
        try withOIDCRedirectAuthProjectLock { try oidcRedirectAuthStore.load() }
    }

    func consumeOIDCRedirectAuth(_ pending: PendingOIDCRedirectAuth) throws -> Bool {
        try withOIDCRedirectAuthProjectLock {
            let flowIdentifier = pending.flowIdentifier
            guard let current = try oidcRedirectAuthStore.load(),
                  current.flowIdentifier == flowIdentifier,
                  !current.isConsumed else {
                return false
            }
            try oidcRedirectAuthStore.save(current.markingConsumed())
            return true
        }
    }

    func clearPendingOIDCRedirectAuthBestEffort(_ pending: PendingOIDCRedirectAuth) {
        try? withOIDCRedirectAuthProjectLock {
            guard let current = try oidcRedirectAuthStore.load(),
                  current.flowIdentifier == pending.flowIdentifier else {
                return
            }
            try oidcRedirectAuthStore.clear()
        }
    }

    func withOIDCRedirectAuthOwnership<T>(
        _ pending: PendingOIDCRedirectAuth,
        _ body: () throws -> T
    ) throws -> T {
        try withOIDCRedirectAuthProjectLock {
            guard let current = try oidcRedirectAuthStore.load(),
                  current.flowIdentifier == pending.flowIdentifier,
                  current.isConsumed else {
                throw OIDCRedirectAuthError.staleFlow
            }
            return try body()
        }
    }

    deinit {
        withSessionLock {
            sessionExpiryTask?.cancel()
            sessionExpiryTask = nil
            _cancelRestoreRead?()
            _cancelRestoreRead = nil
        }
    }

    init(
        publishableKey: String,
        projectId: String,
        environment: OMSWalletEnvironment,
        walletImportTrustedPcr0s: Set<String>? = nil
    ) {
        self.projectId = projectId
        self.environment = environment
        let credentialSession = WalletCredentialSession(environment: environment, projectId: projectId)
        let storedWallet = credentialSession.storedMetadata()
        self.oidcRedirectAuthStore = KeychainOIDCRedirectAuthStore(projectId: projectId, environment: environment)
        self.oidcRedirectAuthLock = OIDCRedirectAuthLockRegistry.lock(
            for: Constants.oidcRedirectAuthStorageKey(environment: environment, scope: projectId)
        )
        self.oidcNonceGenerator = OIDCRedirectAuth.generateNonce
        self.currentDate = Date.init
        self.runWhenActive = ForegroundActivation.runWhenActive
        let makeSignedClient: (any CredentialSigner) -> WaasClient = { signer in
            Self.makeSignedClient(
                publishableKey: publishableKey,
                projectId: projectId,
                environment: environment,
                signer: signer
            )
        }
        self.signedClientFactory = makeSignedClient
        self.walletImportClient = walletImportTrustedPcr0s.map {
            Self.makeWalletImportClient(
                publishableKey: publishableKey,
                projectId: projectId,
                environment: environment,
                signer: credentialSession.signer,
                trustedPcr0s: $0
            )
        }

        self._activeWallet = nil
        self._sessionExpiresAt = nil
        self._sessionAuth = nil
        self.credentialSession = credentialSession

        self._signedClient = makeSignedClient(credentialSession.signer)
        self.publicClient = Self.makePublicClient(
            publishableKey: publishableKey,
            environment: environment
        )
        self.indexerClient = IndexerClient(
            publishableKey: publishableKey,
            environment: environment
        )
        observeSessionCredentialClients()
        restoreStoredWalletSession(storedWallet)
    }

    init(
        publishableKey: String,
        projectId: String,
        environment: OMSWalletEnvironment,
        credentialSession: WalletCredentialSession,
        signedClient: WaasClient,
        publicClient: WaasPublicClient,
        indexerClient: IndexerClient? = nil,
        oidcRedirectAuthStore: (any OIDCRedirectAuthStore)? = nil,
        oidcNonceGenerator: @escaping () throws -> String = OIDCRedirectAuth.generateNonce,
        signedClientFactory: ((any CredentialSigner) -> WaasClient)? = nil,
        currentDate: @escaping () -> Date = Date.init,
        runWhenActive: @escaping (@escaping @Sendable () -> Void) -> ForegroundActivation.Cancel = ForegroundActivation.runWhenActive,
        walletImportClient: WaasClient? = nil
    ) {
        self.projectId = projectId
        self.environment = environment
        let storedWallet = credentialSession.storedMetadata()
        self.oidcRedirectAuthStore = oidcRedirectAuthStore ?? KeychainOIDCRedirectAuthStore(projectId: projectId, environment: environment)
        self.oidcRedirectAuthLock = OIDCRedirectAuthLockRegistry.lock(
            for: Constants.oidcRedirectAuthStorageKey(environment: environment, scope: projectId)
        )
        self.oidcNonceGenerator = oidcNonceGenerator
        self.currentDate = currentDate
        self.runWhenActive = runWhenActive
        let makeSignedClient = signedClientFactory ?? { _ in signedClient }
        self.signedClientFactory = makeSignedClient

        self._activeWallet = nil
        self._sessionExpiresAt = nil
        self._sessionAuth = nil
        self.credentialSession = credentialSession
        self._signedClient = signedClient
        self.walletImportClient = walletImportClient
        self.publicClient = publicClient
        self.indexerClient = indexerClient ?? IndexerClient(
            publishableKey: publishableKey,
            environment: environment
        )
        observeSessionCredentialClients()
        restoreStoredWalletSession(storedWallet)
    }

    /// Routes the clients that sign with the session credential through
    /// `SessionCredentialTransport`. The public client is never wrapped: its errors (for example
    /// `inspectRemoteCredential`'s 7202 for an unknown remote credential) say nothing about the
    /// session.
    private func observeSessionCredentialClients() {
        _signedClient = observingSessionCredential(_signedClient)
        walletImportClient = walletImportClient.map(observingSessionCredential)
    }

    func observingSessionCredential(_ client: WaasClient) -> WaasClient {
        WaasClient(
            baseURL: client.baseURL,
            transport: SessionCredentialTransport(
                base: client.transport,
                gate: signedRequestGate,
                activeSessionRevision: { [weak self] in self?.activeWalletSessionRevision() },
                onRequestCompleted: { [weak self] path in
                    self?.recordSessionCredentialRequestCompleted(path: path)
                },
                onResponse: { [weak self] response, path, revision in
                    self?.handleSessionCredentialResponse(response, path: path, revision: revision)
                }
            ),
            headers: client.headers
        )
    }

    @discardableResult
    public func addSessionExpiredObserver(
        _ observer: @escaping @MainActor @Sendable (OMSWalletSessionExpiredEvent) -> Void
    ) -> OMSWalletSessionExpiredObservation {
        let observerId = UUID()
        let replayEvent = withSessionLock { () -> OMSWalletSessionExpiredEvent? in
            _sessionExpiredObservers[observerId] = observer
            return _latestSessionExpiredEvent
        }
        if let replayEvent {
            Task { @MainActor [weak self] in
                guard self?.shouldReplaySessionExpiredEvent(replayEvent, to: observerId) == true else {
                    return
                }
                observer(replayEvent)
            }
        }
        return OMSWalletSessionExpiredObservation { [weak self] in
            self?.removeSessionExpiredObserver(observerId)
        }
    }

    func removeSessionExpiredObserver(_ observerId: UUID) {
        withSessionLock {
            _sessionExpiredObservers[observerId] = nil
        }
    }

    func sessionExpiredObserversLocked() -> [SessionExpiredObserverRegistration] {
        _sessionExpiredObservers.map { (id: $0.key, observer: $0.value) }
    }

    func shouldReplaySessionExpiredEvent(
        _ event: OMSWalletSessionExpiredEvent,
        to observerId: UUID
    ) -> Bool {
        withSessionLock {
            _sessionExpiredObservers[observerId] != nil && _latestSessionExpiredEvent == event
        }
    }

    func isSessionExpiredObserverRegistered(_ observerId: UUID) -> Bool {
        withSessionLock { _sessionExpiredObservers[observerId] != nil }
    }

    func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        sessionLock.lock()
        defer {
            sessionLock.unlock()
        }
        return try body()
    }

    func withOIDCRedirectAuthProjectLock<T>(_ body: () throws -> T) rethrows -> T {
        oidcRedirectAuthLock.lock()
        defer { oidcRedirectAuthLock.unlock() }
        return try body()
    }

    func sessionRevisionSnapshot() -> UInt64 {
        withSessionLock { _sessionRevision }
    }

    func requireCurrentSessionRevision(_ revision: UInt64) throws {
        try withSessionLock {
            try requireCurrentSessionRevisionLocked(revision)
        }
    }

    func requireCurrentSessionRevisionLocked(_ revision: UInt64) throws {
        guard _sessionRevision == revision else {
            throw OMSWalletError.sessionMissing()
        }
    }

    func requireWalletSelectionOrActiveSession() async throws {
        try await refreshLocallyExpiredSession()
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OMSWalletError.sessionExpired()
        }
        let hasActiveSession = withSessionLock { () -> Bool in
            let hasWallet = !(_activeWallet?.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasVerifiedAuth = !(_sessionExpiresAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasWallet || hasVerifiedAuth
        }
        guard hasActiveSession else {
            throw OMSWalletError.sessionMissing()
        }
    }

    func requireActiveWalletId() async throws -> String {
        try await refreshLocallyExpiredSession()
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OMSWalletError.sessionExpired()
        }
        let walletId = self.walletId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !walletId.isEmpty else {
            throw OMSWalletError.sessionMissing()
        }
        return walletId
    }

    func requireActiveWalletAddress() throws -> String {
        guard let activeWallet else {
            throw OMSWalletError.sessionMissing()
        }
        return activeWallet.address
    }

    func walletAddressIfNeeded(for selectFeeOption: FeeOptionSelector?) throws -> String? {
        guard selectFeeOption != nil else {
            return nil
        }
        return try requireActiveWalletAddress()
    }

    func requireActiveCredential() throws {
        guard try credentialSession.signer.hasCredential() else {
            throw OMSWalletError.sessionMissing()
        }
    }

    /// Persists the given wallet and signer metadata to the keychain
    /// so the session can be restored on a later launch.
    ///
    /// - Parameter wallet: The wallet returned by `createWallet`, `useWallet`, or wallet import.
    func createSequenceWallet(
        wallet: Wallet,
        sessionMetadata: SessionMetadata,
        requiredSessionRevision: UInt64,
        oidcRedirectAuthOwnership: PendingOIDCRedirectAuth? = nil
    ) throws {
        guard StorableCredentials.isValidStoredWallet(wallet) else {
            throw OMSWalletError(
                code: .invalidResponse,
                message: "Wallet response has an unsupported wallet type or key origin"
            )
        }
        let persist = {
            try self.withSessionLock {
                try self.requireCurrentSessionRevisionLocked(requiredSessionRevision)
                // Within the same session only the wallet changes: the session's current metadata
                // wins over `sessionMetadata`, captured before the activation request, so an expiry
                // read applied meanwhile is not rolled back. Sign-in set it before activating.
                let metadata = self.currentSessionMetadataLocked() ?? sessionMetadata
                try self.credentialSession.persist(
                    wallet: wallet,
                    expiresAt: metadata.expiresAt,
                    auth: metadata.auth,
                    expiryBounds: metadata.expiryBounds
                )
                self._latestSessionExpiredEvent = nil
                self._activeWallet = wallet
                self._sessionExpiresAt = metadata.expiresAt
                self._sessionAuth = metadata.auth
                self._sessionExpiryBounds = metadata.expiryBounds
                // Sign-in counts as a refresh; a wallet switch keeps the existing refresh time.
                if self._lastCredentialRefreshAt == nil {
                    self._lastCredentialRefreshAt = self.currentDate()
                }
            }
            if let snapshot = self.currentSessionSnapshot() {
                self.scheduleSessionExpiry(snapshot)
            }
        }
        if let oidcRedirectAuthOwnership {
            try withOIDCRedirectAuthOwnership(oidcRedirectAuthOwnership, persist)
        } else {
            try persist()
        }
    }

    private static func makeSignedClient(
        publishableKey: String,
        projectId: String,
        environment: OMSWalletEnvironment,
        signer: any CredentialSigner
    ) -> WaasClient {
        return WaasClient(
            baseURL: environment.walletApiUrl,
            transport: SignedWaasTransport(
                publishableKey: publishableKey,
                scope: projectId,
                signer: signer
            ),
            headers: { [:] }
        )
    }

    private static func makePublicClient(
        publishableKey: String,
        environment: OMSWalletEnvironment
    ) -> WaasPublicClient {
        return WaasPublicClient(
            baseURL: environment.walletApiUrl,
            headers: {
                [
                    "Api-Key": publishableKey
                ]
            }
        )
    }

    private static func makeWalletImportClient(
        publishableKey: String,
        projectId: String,
        environment: OMSWalletEnvironment,
        signer: any CredentialSigner,
        trustedPcr0s: Set<String>
    ) -> WaasClient {
        WaasClient(
            baseURL: environment.walletApiUrl,
            transport: AttestedSignedWaasTransport(
                publishableKey: publishableKey,
                scope: projectId,
                signer: signer,
                trustedPcr0s: trustedPcr0s
            ),
            headers: { [:] }
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
public final class OMSWalletSessionExpiredObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    public func cancel() {
        lock.lock()
        let onCancel = self.onCancel
        self.onCancel = nil
        lock.unlock()
        onCancel?()
    }
}
