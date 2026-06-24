import Foundation

@available(macOS 12.0, iOS 15.0, *)
public class WalletClient: @unchecked Sendable {
    typealias SessionExpiredNotification = (
        handler: ((SessionExpiredEvent) -> Void)?,
        event: SessionExpiredEvent
    )

    private static let defaultSessionLifetimeSeconds: UInt32 = 604_800
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
    let indexerClient: any WalletIndexerClient
    
    let projectId: String
    let publishableKey: String
    let environment: OMSClientEnvironment
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
    private var _sessionLoginType: SessionLoginType?
    var sessionLoginType: SessionLoginType? {
        get {
            withSessionLock { _sessionLoginType }
        }
        set {
            withSessionLock { _sessionLoginType = newValue }
        }
    }
    private var _sessionEmail: String?
    var sessionEmail: String? {
        get {
            withSessionLock { _sessionEmail }
        }
        set {
            withSessionLock { _sessionEmail = newValue }
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
    private var _latestSessionExpiredEvent: SessionExpiredEvent?
    var latestSessionExpiredEvent: SessionExpiredEvent? {
        get {
            withSessionLock { _latestSessionExpiredEvent }
        }
        set {
            withSessionLock { _latestSessionExpiredEvent = newValue }
        }
    }
    private var _walletAddress: String
    private var _walletId: String
    private var _onSessionExpired: ((SessionExpiredEvent) -> Void)?
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
    public var onSessionExpired: ((SessionExpiredEvent) -> Void)? {
        get {
            withSessionLock { _onSessionExpired }
        }
        set {
            let event = withSessionLock { () -> SessionExpiredEvent? in
                _onSessionExpired = newValue
                return _latestSessionExpiredEvent
            }
            if let event {
                newValue?(event)
            }
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

    public convenience init(
        publishableKey: String,
        walletOrigin: String? = nil
    ) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            projectId: parsedKey.projectId,
            environment: parsedKey.environment(walletOrigin: walletOrigin)
        )
    }

    public convenience init(
        publishableKey: String,
        environment: OMSClientEnvironment
    ) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            projectId: parsedKey.projectId,
            environment: environment
        )
    }

    init(publishableKey: String, projectId: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.projectId = projectId
        self.publishableKey = publishableKey
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
        self._sessionLoginType = nil
        self._sessionEmail = nil
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
        environment: OMSClientEnvironment = OMSClientEnvironment(),
        credentialSession: WalletCredentialSession,
        signedClient: WaasClient,
        publicClient: WaasPublicClient,
        indexerClient: (any WalletIndexerClient)? = nil,
        oidcRedirectAuthStore: (any OidcRedirectAuthStore)? = nil,
        oidcNonceGenerator: @escaping () throws -> String = OidcRedirectAuth.generateNonce,
        signedClientFactory: ((any CredentialSigner) -> WaasClient)? = nil,
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.projectId = projectId
        self.publishableKey = publishableKey
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
        self._sessionLoginType = nil
        self._sessionEmail = nil
        self.credentialSession = credentialSession
        self._signedClient = signedClient
        self.publicClient = publicClient
        self.indexerClient = indexerClient ?? IndexerClient(
            publishableKey: publishableKey,
            environment: environment
        )
        restoreStoredWalletSession(storedWallet)
    }

    func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        sessionLock.lock()
        defer {
            sessionLock.unlock()
        }
        return try body()
    }

    func requireWalletSelectionOrActiveSession() throws {
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OmsSdkError.sessionMissing()
        }
        let hasActiveSession = withSessionLock { () -> Bool in
            let hasWallet = !_walletId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasVerifiedAuth = !(_sessionExpiresAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasWallet || hasVerifiedAuth
        }
        guard hasActiveSession else {
            throw OmsSdkError.sessionMissing()
        }
    }

    func requireActiveWalletId() throws -> String {
        if let notification = expireCurrentSessionIfNeeded() {
            deliverSessionExpiredNotification(notification)
            throw OmsSdkError.sessionMissing()
        }
        let walletId = withSessionLock {
            _walletId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !walletId.isEmpty else {
            throw OmsSdkError.sessionMissing()
        }
        return walletId
    }

    func requireActiveWalletAddress() throws -> String {
        guard let walletAddress else {
            throw OmsSdkError.sessionMissing()
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
            throw OmsSdkError.sessionExpired()
        }
    }

    /// Persists the given wallet address and signer metadata to the keychain
    /// so the session can be restored on a later launch.
    ///
    /// - Parameter address: The on-chain address returned by `createWallet` or `useWallet`.
    func createSequenceWallet(
        walletAddress: String,
        walletId: String,
        sessionMetadata: SessionMetadata
    ) throws {
        withSessionLock {
            _walletAddress = walletAddress
            _walletId = walletId
            _sessionExpiresAt = sessionMetadata.expiresAt
            _sessionLoginType = sessionMetadata.loginType
            _sessionEmail = sessionMetadata.sessionEmail
        }

        try credentialSession.persist(
            walletId: walletId,
            walletAddress: walletAddress,
            expiresAt: sessionMetadata.expiresAt,
            loginType: sessionMetadata.loginType,
            sessionEmail: sessionMetadata.sessionEmail
        )
        scheduleSessionExpiry(session)
    }

    private static func makeSignedClient(
        publishableKey: String,
        projectId: String,
        environment: OMSClientEnvironment,
        signer: any CredentialSigner
    ) -> WaasClient {
        return WaasClient(
            baseURL: environment.walletApiUrl,
            transport: SignedWaasTransport(
                publishableKey: publishableKey,
                scope: projectId,
                signer: signer,
                origin: environment.walletOrigin
            ),
            headers: { [:] }
        )
    }

    private static func makePublicClient(
        publishableKey: String,
        environment: OMSClientEnvironment
    ) -> WaasPublicClient {
        return WaasPublicClient(
            baseURL: environment.walletApiUrl,
            headers: {
                var headers = [
                    "Api-Key": publishableKey
                ]
                if let origin = environment.walletOrigin {
                    headers["Origin"] = origin
                }
                return headers
            }
        )
    }
}
