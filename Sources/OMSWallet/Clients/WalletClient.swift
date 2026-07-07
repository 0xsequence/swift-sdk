import Foundation

@available(macOS 12.0, iOS 15.0, *)
public final class WalletClient: @unchecked Sendable {
    typealias SessionExpiredObserver = (OMSWalletSessionExpiredEvent) -> Void
    typealias SessionExpiredNotification = (
        observers: [SessionExpiredObserver],
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
    let oidcRedirectAuthStore: any OidcRedirectAuthStore
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

    deinit {
        withSessionLock {
            sessionExpiryTask?.cancel()
            sessionExpiryTask = nil
        }
    }

    public convenience init(
        publishableKey: String
    ) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            projectId: parsedKey.projectId,
            environment: parsedKey.environment()
        )
    }

    public convenience init(
        publishableKey: String,
        environment: OMSWalletEnvironment
    ) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            projectId: parsedKey.projectId,
            environment: environment
        )
    }

    init(publishableKey: String, projectId: String, environment: OMSWalletEnvironment) {
        self.projectId = projectId
        self.environment = environment
        let credentialSession = WalletCredentialSession(environment: environment, projectId: projectId)
        let storedWallet = credentialSession.storedMetadata()
        self.oidcRedirectAuthStore = KeychainOidcRedirectAuthStore(projectId: projectId, environment: environment)
        self.oidcNonceGenerator = OidcRedirectAuth.generateNonce
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
        oidcRedirectAuthStore: (any OidcRedirectAuthStore)? = nil,
        oidcNonceGenerator: @escaping () throws -> String = OidcRedirectAuth.generateNonce,
        signedClientFactory: ((any CredentialSigner) -> WaasClient)? = nil,
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.projectId = projectId
        self.environment = environment
        let storedWallet = credentialSession.storedMetadata()
        self.oidcRedirectAuthStore = oidcRedirectAuthStore ?? KeychainOidcRedirectAuthStore(projectId: projectId, environment: environment)
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
        _ observer: @escaping (OMSWalletSessionExpiredEvent) -> Void
    ) -> OMSWalletSessionExpiredObservation {
        let observerId = UUID()
        let replayEvent = withSessionLock { () -> OMSWalletSessionExpiredEvent? in
            _sessionExpiredObservers[observerId] = observer
            return _latestSessionExpiredEvent
        }
        if let replayEvent {
            observer(replayEvent)
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

    func sessionExpiredObserversLocked() -> [SessionExpiredObserver] {
        Array(_sessionExpiredObservers.values)
    }

    func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        sessionLock.lock()
        defer {
            sessionLock.unlock()
        }
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
        requiredSessionRevision: UInt64
    ) throws {
        try withSessionLock {
            try requireCurrentSessionRevisionLocked(requiredSessionRevision)
            try credentialSession.persist(
                walletId: walletId,
                walletAddress: walletAddress,
                expiresAt: sessionMetadata.expiresAt,
                auth: sessionMetadata.auth
            )
            _latestSessionExpiredEvent = nil
            _walletAddress = walletAddress
            _walletId = walletId
            _sessionExpiresAt = sessionMetadata.expiresAt
            _sessionAuth = sessionMetadata.auth
        }
        scheduleSessionExpiry(session)
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
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
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
