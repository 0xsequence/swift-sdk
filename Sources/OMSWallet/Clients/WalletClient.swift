import Foundation

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
            withSessionLock { _signedClient = newValue }
        }
    }
    var publicClient: WaasPublicClient
    let indexerClient: IndexerClient
    
    let projectId: String
    let environment: OMSWalletEnvironment
    let credentialSession: WalletCredentialSession
    let oidcRedirectAuthStore: any OIDCRedirectAuthStore
    private let oidcRedirectAuthLock: NSRecursiveLock
    let oidcNonceGenerator: () throws -> String
    let signedClientFactory: (any CredentialSigner) -> WaasClient
    let currentDate: () -> Date
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
    private var _latestSessionExpiredEvent: OMSWalletSessionExpiredEvent?
    var latestSessionExpiredEvent: OMSWalletSessionExpiredEvent? {
        get {
            withSessionLock { _latestSessionExpiredEvent }
        }
        set {
            withSessionLock { _latestSessionExpiredEvent = newValue }
        }
    }
    private var _walletAddress: String
    private var _walletId: String
    var _sessionRevision: UInt64 = 0
    private var _sessionExpiredObservers: [UUID: SessionExpiredObserver] = [:]
    private var _verifier = ""
    private var _challenge = ""
    private var _pendingEmailAuthSessionLifetimeSeconds: UInt32?

    public internal(set) var walletAddress: String? {
        get {
            withSessionLock {
                let walletAddress = _walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                return walletAddress.isEmpty ? nil : walletAddress
            }
        }
        set {
            withSessionLock { _walletAddress = newValue ?? "" }
        }
    }
    public internal(set) var walletId: String {
        get {
            withSessionLock { _walletId }
        }
        set {
            withSessionLock { _walletId = newValue }
        }
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
    var pendingEmailAuthSessionLifetimeSeconds: UInt32? {
        get {
            withSessionLock { _pendingEmailAuthSessionLifetimeSeconds }
        }
        set {
            withSessionLock { _pendingEmailAuthSessionLifetimeSeconds = newValue }
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

    func clearAllPendingOIDCRedirectAuth() throws {
        try withOIDCRedirectAuthProjectLock { try oidcRedirectAuthStore.clear() }
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
        }
    }

    init(publishableKey: String, projectId: String, environment: OMSWalletEnvironment) {
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
        let makeSignedClient: (any CredentialSigner) -> WaasClient = { signer in
            Self.makeSignedClient(
                publishableKey: publishableKey,
                projectId: projectId,
                environment: environment,
                signer: signer
            )
        }
        self.signedClientFactory = makeSignedClient

        self._walletId = ""
        self._walletAddress = ""
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
        currentDate: @escaping () -> Date = Date.init
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
        let makeSignedClient = signedClientFactory ?? { _ in signedClient }
        self.signedClientFactory = makeSignedClient

        self._walletId = ""
        self._walletAddress = ""
        self._sessionExpiresAt = nil
        self._sessionAuth = nil
        self.credentialSession = credentialSession
        self._signedClient = signedClient
        self.publicClient = publicClient
        self.indexerClient = indexerClient ?? IndexerClient(
            publishableKey: publishableKey,
            environment: environment
        )
        restoreStoredWalletSession(storedWallet)
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

    func requireWalletSelectionOrActiveSession() throws {
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OMSWalletError.sessionExpired()
        }
        let hasActiveSession = withSessionLock { () -> Bool in
            let hasWallet = !_walletId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasVerifiedAuth = !(_sessionExpiresAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasWallet || hasVerifiedAuth
        }
        guard hasActiveSession else {
            throw OMSWalletError.sessionMissing()
        }
    }

    func requireActiveWalletId() throws -> String {
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OMSWalletError.sessionExpired()
        }
        let walletId = withSessionLock {
            _walletId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !walletId.isEmpty else {
            throw OMSWalletError.sessionMissing()
        }
        return walletId
    }

    func requireActiveWalletAddress() throws -> String {
        guard let walletAddress else {
            throw OMSWalletError.sessionMissing()
        }
        return walletAddress
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

    /// Persists the given wallet address and signer metadata to the keychain
    /// so the session can be restored on a later launch.
    ///
    /// - Parameter address: The on-chain address returned by `createWallet` or `useWallet`.
    func createSequenceWallet(
        walletAddress: String,
        walletId: String,
        sessionMetadata: SessionMetadata,
        requiredSessionRevision: UInt64,
        oidcRedirectAuthOwnership: PendingOIDCRedirectAuth? = nil
    ) throws {
        let persist = {
            try self.withSessionLock {
                try self.requireCurrentSessionRevisionLocked(requiredSessionRevision)
                try self.credentialSession.persist(
                    walletId: walletId,
                    walletAddress: walletAddress,
                    expiresAt: sessionMetadata.expiresAt,
                    auth: sessionMetadata.auth
                )
                self._latestSessionExpiredEvent = nil
                self._walletAddress = walletAddress
                self._walletId = walletId
                self._sessionExpiresAt = sessionMetadata.expiresAt
                self._sessionAuth = sessionMetadata.auth
            }
            self.scheduleSessionExpiry(self.session)
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
