import Foundation

public enum TransactionError: Error {
    case noFeeOptionsAvailable
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}

@available(macOS 12.0, iOS 15.0, *)
public class WalletClient {
    private struct SessionMetadata {
        let expiresAt: String?
        let loginType: SessionLoginType?
        let sessionEmail: String?
    }

    private struct PendingWalletSelectionSession {
        let id: UUID
        let signerCredentialId: String
        let signerKeyType: SigningAlgorithm
        let metadata: SessionMetadata
    }

    private static let defaultSessionLifetimeSeconds: UInt32 = 604_800

    private var signedClient: WaasWalletClient
    private var publicClient: WaasWalletPublicClient
    private let indexerClient: any WalletIndexerClient
    
    private let projectId: String
    private let projectAccessKey: String
    private let environment: OMSClientEnvironment
    private let credentialSession: WalletCredentialSession
    private let oidcRedirectAuthStore: any OidcRedirectAuthStore
    private let oidcNonceGenerator: () throws -> String
    private let signedClientFactory: (any CredentialSigner) -> WaasWalletClient
    private var sessionExpiresAt: String?
    private var sessionLoginType: SessionLoginType?
    private var sessionEmail: String?
    private var activePendingWalletSelection: PendingWalletSelectionSession?

    public var walletAddress: String
    public var walletId: String

    var verifier = "";
    var challenge = "";

    public init(projectAccessKey: String, projectId: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.projectId = projectId
        self.projectAccessKey = projectAccessKey
        self.environment = environment
        let credentialSession = WalletCredentialSession(environment: environment, projectId: projectId)
        let restoredWallet = credentialSession.restore()
        self.oidcRedirectAuthStore = KeychainOidcRedirectAuthStore(projectId: projectId, environment: environment)
        self.oidcNonceGenerator = OidcRedirectAuth.generateNonce
        let makeSignedClient: (any CredentialSigner) -> WaasWalletClient = { signer in
            Self.makeSignedClient(
                projectAccessKey: projectAccessKey,
                projectId: projectId,
                environment: environment,
                signer: signer
            )
        }
        self.signedClientFactory = makeSignedClient

        self.walletId = restoredWallet?.walletId ?? ""
        self.walletAddress = restoredWallet?.walletAddress ?? ""
        self.sessionExpiresAt = restoredWallet?.expiresAt
        self.sessionLoginType = restoredWallet?.loginType
        self.sessionEmail = restoredWallet?.sessionEmail
        self.credentialSession = credentialSession

        self.signedClient = makeSignedClient(credentialSession.signer)
        self.publicClient = Self.makePublicClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )
        self.indexerClient = IndexerClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )
    }

    init(
        projectAccessKey: String,
        projectId: String,
        environment: OMSClientEnvironment = OMSClientEnvironment(),
        credentialSession: WalletCredentialSession,
        signedClient: WaasWalletClient,
        publicClient: WaasWalletPublicClient,
        indexerClient: (any WalletIndexerClient)? = nil,
        oidcRedirectAuthStore: (any OidcRedirectAuthStore)? = nil,
        oidcNonceGenerator: @escaping () throws -> String = OidcRedirectAuth.generateNonce,
        signedClientFactory: ((any CredentialSigner) -> WaasWalletClient)? = nil
    ) {
        self.projectId = projectId
        self.projectAccessKey = projectAccessKey
        self.environment = environment
        let restoredWallet = credentialSession.restore()
        self.oidcRedirectAuthStore = oidcRedirectAuthStore ?? KeychainOidcRedirectAuthStore(projectId: projectId, environment: environment)
        self.oidcNonceGenerator = oidcNonceGenerator
        let makeSignedClient = signedClientFactory ?? { _ in signedClient }
        self.signedClientFactory = makeSignedClient

        self.walletId = restoredWallet?.walletId ?? ""
        self.walletAddress = restoredWallet?.walletAddress ?? ""
        self.sessionExpiresAt = restoredWallet?.expiresAt
        self.sessionLoginType = restoredWallet?.loginType
        self.sessionEmail = restoredWallet?.sessionEmail
        self.credentialSession = credentialSession
        self.signedClient = signedClient
        self.publicClient = publicClient
        self.indexerClient = indexerClient ?? IndexerClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )
    }

    /// Whether there is a persisted OIDC redirect flow that can still be completed by
    /// passing the app callback URL to `handleOidcRedirectCallback`.
    public var canResumeOidcRedirectAuth: Bool {
        (try? oidcRedirectAuthStore.load()) != nil
    }

    /// Snapshot of the current durable wallet-session state.
    public var session: SessionState {
        guard !walletAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SessionState(walletAddress: nil)
        }

        return SessionState(
            walletAddress: walletAddress,
            expiresAtString: sessionExpiresAt,
            loginType: sessionLoginType,
            sessionEmail: sessionEmail
        )
    }

    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method ensures a request-signing credential exists and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `completeEmailAuth(code:walletType:walletSelection:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func startEmailAuth(email: String) async throws {
        try signOut()

        do {
            let params = CommitVerifierRequest(
                identityType: IdentityType.email,
                authMode: AuthMode.otp,
                metadata: [String : String] (),
                handle: email
            )

            let response = try await signedClient.commitVerifier(params)

            verifier = response.verifier
            challenge = response.challenge
        } catch {
            try? signOut()
            throw error
        }
    }

    /// Completes the email OTP authentication flow.
    ///
    /// With `.automatic`, this selects the first existing wallet matching `walletType`,
    /// or creates one when none exists. With `.manual`, this verifies auth and returns
    /// a `PendingWalletSelection` so the app can select or create a wallet later.
    @discardableResult
    public func completeEmailAuth(
        code: String,
        walletType: WalletType = WalletType.ethereum,
        walletSelection: WalletSelectionBehavior = .automatic
    ) async throws -> CompleteAuthResult {
        let response = try await confirmEmailSignIn(code: code)
        return try await completeWalletAuth(
            response,
            walletType: walletType,
            walletSelection: walletSelection
        )
    }

    /// Starts OIDC authorization-code PKCE redirect authentication.
    ///
    /// Open the returned `authorizationUrl` in a browser or `ASWebAuthenticationSession`.
    /// After the provider redirects back to your app, pass the callback URL to
    /// `handleOidcRedirectCallback(_:walletSelection:)`.
    public func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String,
        walletType: WalletType = WalletType.ethereum,
        authorizeParams: [String: String] = [:]
    ) async throws -> StartOidcRedirectAuthResult {
        try await startOidcRedirectAuth(
            provider: provider,
            redirectUri: redirectUri,
            walletType: walletType,
            relayRedirectUri: provider.relayRedirectUri,
            authorizeParams: authorizeParams
        )
    }

    /// Starts OIDC authorization-code PKCE redirect authentication with an explicit
    /// OAuth redirect URI override. Pass `nil` to use the app callback URI directly
    /// even when the provider configuration has a relay redirect URI.
    public func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String,
        walletType: WalletType = WalletType.ethereum,
        relayRedirectUri: String?,
        authorizeParams: [String: String] = [:]
    ) async throws -> StartOidcRedirectAuthResult {
        try clearSession(clearOidcRedirectAuth: true)

        do {
            let signerCredentialId = try credentialSession.signer.credentialId()
            let oauthRedirectUri = relayRedirectUri ?? redirectUri
            let response = try await signedClient.commitVerifier(
                CommitVerifierRequest(
                    identityType: .oidc,
                    authMode: .authCodePkce,
                    metadata: [
                        "iss": provider.issuer,
                        "aud": provider.clientId,
                        "redirect_uri": oauthRedirectUri
                    ]
                )
            )
            let nonce = try oidcNonceGenerator()
            let state = try OidcRedirectAuth.encodeState(
                nonce: nonce,
                scope: projectId,
                redirectUri: oauthRedirectUri == redirectUri ? nil : redirectUri
            )

            verifier = response.verifier
            challenge = response.challenge
            try oidcRedirectAuthStore.save(
                PendingOidcRedirectAuth(
                    verifier: response.verifier,
                    challenge: response.challenge,
                    nonce: nonce,
                    redirectUri: redirectUri,
                    issuer: provider.issuer,
                    authorizationScope: self.projectId,
                    walletType: walletType,
                    signerCredentialId: signerCredentialId,
                    signerKeyType: credentialSession.signer.alg
                )
            )

            let authorizationUrl = try OidcRedirectAuth.buildAuthorizationUrl(
                provider: provider,
                redirectUri: oauthRedirectUri,
                state: state,
                challenge: response.challenge,
                loginHint: response.loginHint,
                authorizeParams: provider.authorizeParams.merging(authorizeParams) { _, new in new }
            )

            return StartOidcRedirectAuthResult(
                authorizationUrl: authorizationUrl,
                state: state,
                challenge: response.challenge
            )
        } catch {
            try? clearSession(clearOidcRedirectAuth: true)
            throw error
        }
    }

    /// Safely handles an incoming OIDC authorization-code PKCE redirect callback.
    ///
    /// This method is idempotent and safe to call for every incoming app link.
    /// Unrelated links return `.notOidcRedirectCallback`, stale callbacks return
    /// `.noPendingAuth`, and successful auth returns `.completed` or
    /// `.walletSelection` when `walletSelection` is `.manual`.
    public func handleOidcRedirectCallback(
        _ callbackUrl: String?,
        walletSelection: WalletSelectionBehavior = .automatic
    ) async throws -> OidcRedirectAuthResult {
        guard let callbackUrl = callbackUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callbackUrl.isEmpty else {
            return .notOidcRedirectCallback
        }

        let callback = OidcRedirectAuth.parseCallbackUrl(callbackUrl)
        guard callback.hasOidcResponse else {
            return .notOidcRedirectCallback
        }

        let pending: PendingOidcRedirectAuth
        do {
            guard let loaded = try oidcRedirectAuthStore.load() else {
                return .noPendingAuth
            }
            pending = loaded
        } catch {
            return .noPendingAuth
        }

        guard OidcRedirectAuth.matchesRedirectUri(
            callbackUrl: callbackUrl,
            redirectUri: pending.redirectUri
        ) else {
            return .notOidcRedirectCallback
        }

        guard let state = callback.state,
              (try? OidcRedirectAuth.validateState(state, pending: pending)) != nil else {
            return .notOidcRedirectCallback
        }

        var clearPendingAuth = false
        defer {
            if clearPendingAuth {
                try? oidcRedirectAuthStore.clear()
            }
        }

        do {
            clearPendingAuth = true
            if let error = callback.error {
                throw OidcRedirectAuthError.providerError(
                    callback.errorDescription ?? "OIDC provider returned error: \(error)"
                )
            }
            guard let code = callback.code else {
                throw OidcRedirectAuthError.missingCode
            }

            try restorePendingOidcRedirectAuth(pending)
            let response = try await signedClient.completeAuth(
                CompleteAuthRequest(
                    identityType: .oidc,
                    authMode: .authCodePkce,
                    verifier: pending.verifier,
                    answer: code,
                    lifetime: Self.defaultSessionLifetimeSeconds
                )
            )
            let result = try await completeWalletAuth(
                response,
                walletType: pending.walletType,
                walletSelection: walletSelection
            )

            switch result {
            case .walletSelected(_, let wallet, _, _):
                return .completed(wallet: wallet)
            case .walletSelection(let pendingSelection):
                return .walletSelection(pendingSelection)
            }
        } catch let error as CancellationError {
            clearPendingAuth = false
            throw error
        } catch {
            try? clearSession(clearOidcRedirectAuth: false)
            return .failed(error)
        }
    }

    private func confirmEmailSignIn(code: String) async throws -> CompleteAuthResponse {
        let answer = RequestUtils.hashEmailAuthAnswer(challenge: challenge, code: code)

        let params = CompleteAuthRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            verifier: verifier,
            answer: answer,
            lifetime: Self.defaultSessionLifetimeSeconds
        )

        return try await signedClient.completeAuth(params)
    }

    private func completeWalletAuth(
        _ response: CompleteAuthResponse,
        walletType: WalletType,
        walletSelection: WalletSelectionBehavior
    ) async throws -> CompleteAuthResult {
        activePendingWalletSelection = nil

        let sessionMetadata = SessionMetadata(
            expiresAt: response.credential.expiresAt,
            loginType: OMSClientIdentity(response.identity).sessionLoginType,
            sessionEmail: response.email
        )
        self.sessionExpiresAt = sessionMetadata.expiresAt
        self.sessionLoginType = sessionMetadata.loginType
        self.sessionEmail = sessionMetadata.sessionEmail

        let wallets = try await signOutOnFailure {
            try await walletsFromAuthResponse(response)
        }

        let candidateWallets = wallets.filter { $0.type == walletType }
        guard walletSelection == .automatic else {
            let pendingSelectionSession = try beginPendingWalletSelection(sessionMetadata: sessionMetadata)
            return .walletSelection(
                pendingWalletSelection(
                    walletType: walletType,
                    wallets: candidateWallets,
                    credential: response.credential,
                    selectionSession: pendingSelectionSession
                )
            )
        }

        let activated: WalletActivationResult
        if let selectedWallet = candidateWallets.first {
            activated = try await signOutOnFailure {
                try await useWallet(
                    walletId: selectedWallet.id,
                    sessionMetadata: sessionMetadata
                )
            }
        } else {
            activated = try await signOutOnFailure {
                try await createWallet(
                    walletType: walletType,
                    sessionMetadata: sessionMetadata
                )
            }
        }

        return .walletSelected(
            walletAddress: activated.walletAddress,
            wallet: activated.wallet,
            wallets: candidateWallets.isEmpty ? wallets + [activated.wallet] : wallets,
            credential: response.credential
        )
    }

    private func pendingWalletSelection(
        walletType: WalletType,
        wallets: [Wallet],
        credential: CredentialInfo,
        selectionSession: PendingWalletSelectionSession
    ) -> PendingWalletSelection {
        PendingWalletSelection(
            walletType: walletType,
            wallets: wallets,
            credential: credential,
            selectWalletAction: { walletId in
                try self.requireActivePendingWalletSelection(selectionSession)
                let result = try await self.useWallet(
                    walletId: walletId,
                    sessionMetadata: selectionSession.metadata
                )
                self.activePendingWalletSelection = nil
                return result
            },
            createAndSelectWalletAction: { reference in
                try self.requireActivePendingWalletSelection(selectionSession)
                let result = try await self.createWallet(
                    walletType: walletType,
                    reference: reference,
                    sessionMetadata: selectionSession.metadata
                )
                self.activePendingWalletSelection = nil
                return result
            }
        )
    }

    private func beginPendingWalletSelection(
        sessionMetadata: SessionMetadata
    ) throws -> PendingWalletSelectionSession {
        let selectionSession = PendingWalletSelectionSession(
            id: UUID(),
            signerCredentialId: try credentialSession.signer.credentialId(),
            signerKeyType: credentialSession.signer.alg,
            metadata: sessionMetadata
        )
        activePendingWalletSelection = selectionSession
        return selectionSession
    }

    private func requireActivePendingWalletSelection(
        _ selectionSession: PendingWalletSelectionSession
    ) throws {
        guard activePendingWalletSelection?.id == selectionSession.id else {
            throw WalletAuthError.staleWalletSelection
        }
        try requireActiveCredential()
        let signerCredentialId = try credentialSession.signer.credentialId()
        guard signerCredentialId.lowercased() == selectionSession.signerCredentialId.lowercased(),
              credentialSession.signer.alg == selectionSession.signerKeyType else {
            throw WalletAuthError.staleWalletSelection
        }
    }

    private func signOutOnFailure<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch {
            try? signOut()
            throw error
        }
    }

    /// Activates an existing wallet by its WaaS wallet ID and persists its address and
    /// signer metadata to the keychain.
    @discardableResult
    public func useWallet(walletId: String) async throws -> WalletActivationResult {
        try requireWalletSelectionOrActiveSession()
        try requireActiveCredential()
        return try await useWallet(
            walletId: walletId,
            sessionMetadata: currentSessionMetadata()
        )
    }

    /// Creates a new wallet of the specified type for the authenticated user and persists
    /// its address and signer metadata to the keychain.
    ///
    /// Call this after `completeEmailAuth(code:walletType:walletSelection:)` returns
    /// `.walletSelection`, or when an authenticated session already exists.
    ///
    /// - Parameter walletType: The wallet type to create (e.g. `.ethereumEoa`).
    @discardableResult
    public func createWallet(
        walletType: WalletType = WalletType.ethereum,
        reference: String? = nil
    ) async throws -> WalletActivationResult {
        try requireWalletSelectionOrActiveSession()
        try requireActiveCredential()
        return try await createWallet(
            walletType: walletType,
            reference: reference,
            sessionMetadata: currentSessionMetadata()
        )
    }

    /// Lists all wallets available to the authenticated credential.
    public func listWallets() async throws -> [Wallet] {
        try requireWalletSelectionOrActiveSession()
        try requireActiveCredential()
        return try await listWallets(startingAt: nil)
    }

    private func createWallet(
        walletType: WalletType,
        reference: String? = nil,
        sessionMetadata: SessionMetadata
    ) async throws -> WalletActivationResult {
        let params = CreateWalletRequest(
            type: walletType,
            reference: reference
        )

        let response = try await signedClient.createWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata
        )

        return WalletActivationResult(
            walletAddress: response.wallet.address,
            wallet: response.wallet
        )
    }

    /// Loads an existing wallet of the specified type for the authenticated user and persists
    /// its address and signer metadata to the keychain.
    ///
    /// Called internally by auth completion when the user already has
    /// a wallet of the requested type on their account.
    ///
    /// - Parameter walletType: The wallet type to load (e.g. `.ethereumEoa`).
    private func useWallet(walletId: String, sessionMetadata: SessionMetadata) async throws -> WalletActivationResult {
        let params = UseWalletRequest(
            walletId: walletId
        )

        let response = try await signedClient.useWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata
        )

        return WalletActivationResult(
            walletAddress: response.wallet.address,
            wallet: response.wallet
        )
    }

    private func walletsFromAuthResponse(_ response: CompleteAuthResponse) async throws -> [Wallet] {
        var wallets = response.wallets
        if let cursor = nonEmptyCursor(response.page?.cursor) {
            wallets += try await listWallets(startingAt: cursor)
        }
        return wallets
    }

    private func listWallets(startingAt initialCursor: String?) async throws -> [Wallet] {
        var wallets: [Wallet] = []
        var cursor = initialCursor

        repeat {
            let response = try await signedClient.listWallets(
                ListWalletsRequest(
                    page: cursor.map { Page(cursor: $0) }
                )
            )
            wallets += response.wallets
            cursor = nonEmptyCursor(response.page?.cursor)
        } while cursor != nil

        return wallets
    }

    private func nonEmptyCursor(_ cursor: String?) -> String? {
        guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines), !cursor.isEmpty else {
            return nil
        }
        return cursor
    }

    private func currentSessionMetadata() -> SessionMetadata {
        SessionMetadata(
            expiresAt: sessionExpiresAt,
            loginType: sessionLoginType,
            sessionEmail: sessionEmail
        )
    }

    private func requireWalletSelectionOrActiveSession() throws {
        let hasWallet = !walletId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasVerifiedAuth = !(sessionExpiresAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasWallet || hasVerifiedAuth else {
            throw WalletAuthError.noAuthenticatedWalletSession
        }
    }

    private func requireActiveWalletId() throws -> String {
        let walletId = walletId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !walletId.isEmpty else {
            throw WalletAuthError.noAuthenticatedWalletSession
        }
        return walletId
    }

    private func requireActiveWalletAddress() throws -> String {
        let walletAddress = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !walletAddress.isEmpty else {
            throw WalletAuthError.noAuthenticatedWalletSession
        }
        return walletAddress
    }

    private func activeWalletAddressIfNeeded(for feeOptionSelector: FeeOptionSelector?) throws -> String? {
        guard feeOptionSelector != nil else {
            return nil
        }
        return try requireActiveWalletAddress()
    }

    private func requireActiveCredential() throws {
        guard try credentialSession.signer.hasCredential() else {
            throw WalletAuthError.noActiveCredential
        }
    }

    private func restorePendingOidcRedirectAuth(_ pending: PendingOidcRedirectAuth) throws {
        try requireActiveCredential()
        let signerCredentialId = try credentialSession.signer.credentialId()
        guard signerCredentialId.lowercased() == pending.signerCredentialId.lowercased(),
              pending.signerKeyType == nil || pending.signerKeyType == credentialSession.signer.alg else {
            throw OidcRedirectAuthError.signerMismatch
        }

        verifier = pending.verifier
        challenge = pending.challenge
    }

    /// Persists the given wallet address and signer metadata to the keychain
    /// so the session can be restored on a later launch.
    ///
    /// - Parameter address: The on-chain address returned by `createWallet` or `useWallet`.
    private func createSequenceWallet(
        walletAddress: String,
        walletId: String,
        sessionMetadata: SessionMetadata
    ) throws {
        self.walletAddress = walletAddress
        self.walletId = walletId
        self.sessionExpiresAt = sessionMetadata.expiresAt
        self.sessionLoginType = sessionMetadata.loginType
        self.sessionEmail = sessionMetadata.sessionEmail

        try credentialSession.persist(
            walletId: walletId,
            walletAddress: walletAddress,
            expiresAt: sessionMetadata.expiresAt,
            loginType: sessionMetadata.loginType,
            sessionEmail: sessionMetadata.sessionEmail
        )
    }

    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, any attempt to restore the session on the next launch will fail
    /// and the user will need to sign in again via `startEmailAuth(email:)`. Navigate to your
    /// sign-in screen after calling this.
    public func signOut() throws {
        try clearSession(clearOidcRedirectAuth: true)
    }

    private func clearSession(clearOidcRedirectAuth: Bool) throws {
        activePendingWalletSelection = nil
        try credentialSession.clear()
        if clearOidcRedirectAuth {
            try oidcRedirectAuthStore.clear()
        }
        walletAddress = ""
        walletId = ""
        verifier = ""
        challenge = ""
        sessionExpiresAt = nil
        sessionLoginType = nil
        sessionEmail = nil
        signedClient = signedClientFactory(credentialSession.signer)
    }

    /// Returns a list of credentials that currently have access to this wallet.
    ///
    /// Use this to display active sessions or integrations in your app's account
    /// management UI, or to check what credentials exist before revoking one.
    ///
    /// - Returns: An array of `CredentialInfo` values representing each credential
    ///   with access to this wallet.
    public func listAccess() async throws -> [CredentialInfo] {
        let walletId = try requireActiveWalletId()
        let params = ListAccessRequest(
            walletId: walletId
        )

        let response = try await signedClient.listAccess(params)
        return response.credentials
    }
    
    public func getIdToken(ttlSeconds: UInt32? = nil, customClaims: [String: WebRPCJSONValue]? = nil) async throws -> String {
        let walletId = try requireActiveWalletId()
        let params = GetIDTokenRequest(
            walletId: walletId,
            ttlSeconds: ttlSeconds,
            customClaims: customClaims
        )
        
        let response = try await signedClient.getIdToken(params)
        return response.idToken
    }

    /// Revokes access for a specific credential, preventing it from interacting
    /// with this wallet going forward.
    ///
    /// Use `listAccess()` first to retrieve the credential IDs available to revoke.
    /// This action cannot be undone — the credential will need to be re-authorized
    /// to regain access.
    ///
    /// - Parameter targetCredentialId: The unique identifier of the credential to revoke.
    public func revokeAccess(targetCredentialId: String) async throws {
        let walletId = try requireActiveWalletId()
        let params = RevokeAccessRequest(
            targetCredentialId: targetCredentialId,
            walletId: walletId
        )

        _ = try await signedClient.revokeAccess(params)
    }

    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: Network, message: String) async throws -> String {
        let walletId = try requireActiveWalletId()
        let params = SignMessageRequest(
            network: network.chainId,
            walletId: walletId,
            message: message
        )

        let response = try await signedClient.signMessage(params)
        return response.signature
    }

    public func signTypedData(network: Network, typedData: WebRPCJSONValue) async throws -> String {
        let walletId = try requireActiveWalletId()
        let params = SignTypedDataRequest(
            network: network.chainId,
            walletId: walletId,
            typedData: typedData
        )

        let response = try await signedClient.signTypedData(params)
        return response.signature
    }

    public func isValidMessageSignature(
        network: Network,
        walletAddress: String,
        message: String,
        signature: String
    ) async throws -> Bool {
        let walletId = try requireActiveWalletId()
        let response = try await publicClient.isValidMessageSignature(
            IsValidMessageSignatureRequest(
                network: network.chainId,
                walletAddress: walletAddress,
                walletId: walletId,
                message: message,
                signature: signature
            )
        )

        return response.isValid
    }

    public func isValidTypedDataSignature(
        network: Network,
        walletAddress: String,
        typedData: WebRPCJSONValue,
        signature: String
    ) async throws -> Bool {
        let walletId = try requireActiveWalletId()
        let response = try await publicClient.isValidTypedDataSignature(
            IsValidTypedDataSignatureRequest(
                network: network.chainId,
                walletAddress: walletAddress,
                walletId: walletId,
                typedData: typedData,
                signature: signature
            )
        )

        return response.isValid
    }

    public func sendTransaction(
        network: Network,
        to: String,
        value: String,
        feeOptionSelector: FeeOptionSelector? = nil
    ) async throws -> TransactionResult {
        let walletId = try requireActiveWalletId()
        let walletAddress = try activeWalletAddressIfNeeded(for: feeOptionSelector)
        return try await sendTransaction(
            network: network,
            request: SendTransactionRequest(
                to: to,
                value: value,
                data: nil
            ),
            feeOptionSelector: feeOptionSelector,
            walletId: walletId,
            walletAddress: walletAddress
        )
    }

    public func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        feeOptionSelector: FeeOptionSelector? = nil
    ) async throws -> TransactionResult {
        let walletId = try requireActiveWalletId()
        let walletAddress = try activeWalletAddressIfNeeded(for: feeOptionSelector)
        return try await sendTransaction(
            network: network,
            request: request,
            feeOptionSelector: feeOptionSelector,
            walletId: walletId,
            walletAddress: walletAddress
        )
    }

    private func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        feeOptionSelector: FeeOptionSelector?,
        walletId: String,
        walletAddress: String?
    ) async throws -> TransactionResult {
        let prepareResponse = try await signedClient.prepareEthereumTransaction(
            PrepareEthereumTransactionRequest(
                network: network.chainId,
                walletId: walletId,
                to: request.to,
                value: request.value,
                data: request.data,
                mode: .relayer
            )
        )

        return try await self.execute(
            network: network,
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector,
            walletAddress: walletAddress
        );
    }

    public func callContract(
        network: Network,
        contract: String,
        method: String,
        args: [AbiArg]?,
        feeOptionSelector: FeeOptionSelector? = nil
    ) async throws -> TransactionResult {
        let walletId = try requireActiveWalletId()
        let walletAddress = try activeWalletAddressIfNeeded(for: feeOptionSelector)
        let prepareResponse = try await signedClient.prepareEthereumContractCall(
            PrepareEthereumContractCallRequest(
                network: network.chainId,
                walletId: walletId,
                contract: contract,
                method: method,
                args: args,
                mode: .relayer
            )
        )

        return try await self.execute(
            network: network,
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector,
            walletAddress: walletAddress
        );
    }

    /// Returns the current execution status for a prepared or submitted transaction.
    ///
    /// - Parameter txnId: The transaction ID returned by the wallet API prepare/execute flow.
    /// - Returns: The current transaction status and transaction hash when available.
    public func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse {
        return try await signedClient.transactionStatus(
            TransactionStatusRequest(txnId: txnId)
        )
    }

    private func execute(
        network: Network,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        walletAddress: String?
    ) async throws -> TransactionResult {
        let feeOptionSelection = try await selectFeeOption(
            network: network,
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector,
            walletAddress: walletAddress
        )

        let executeRequest = ExecuteRequest(
            txnId: prepareResponse.txnId,
            feeOption: feeOptionSelection
        )

        let executeResponse = try await signedClient.execute(executeRequest)
        var status = executeResponse.status
        if status == .executed {
            return try await getExecutedTransactionResult(txnId: prepareResponse.txnId)
        }

        let pollIntervalNanos: UInt64 = 750_000_000
        let maxAttempts = 10  // ~45s ceiling
        var attempts = 0

        while status == .pending {
            guard attempts < maxAttempts else {
                throw TransactionError.pollingTimedOut
            }
            try await Task.sleep(nanoseconds: pollIntervalNanos)
            attempts += 1

            let statusResponse = try await getTransactionStatus(txnId: prepareResponse.txnId)
            status = statusResponse.status

            if status == .executed {
                let txnHash = try requireTransactionHash(from: statusResponse)
                return TransactionResult(
                    txnId: prepareResponse.txnId,
                    status: statusResponse.status,
                    txnHash: txnHash
                )
            }
        }

        // Loop exited without `.executed` — surface the terminal status.
        throw TransactionError.transactionFailed(status: status)
    }

    private func selectFeeOption(
        network: Network,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        walletAddress: String?
    ) async throws -> FeeOptionSelection? {
        guard !prepareResponse.sponsored else {
            return nil
        }

        guard !prepareResponse.feeOptions.isEmpty else {
            throw TransactionError.noFeeOptionsAvailable
        }

        guard let feeOptionSelector else {
            return prepareResponse.feeOptions.defaultSelection()
        }

        guard let walletAddress else {
            throw WalletAuthError.noAuthenticatedWalletSession
        }

        return try await feeOptionSelector(
            enrichFeeOptionsWithBalances(
                network: network,
                walletAddress: walletAddress,
                feeOptions: prepareResponse.feeOptions
            )
        )
    }

    private func enrichFeeOptionsWithBalances(
        network: Network,
        walletAddress: String,
        feeOptions: [FeeOption]
    ) async -> [FeeOptionWithBalance] {
        let nativeBalance: TokenBalance?
        if feeOptions.contains(where: { $0.token.isNativeToken }) {
            nativeBalance = await loadNativeTokenBalance(
                network: network,
                walletAddress: walletAddress
            )
        } else {
            nativeBalance = nil
        }

        var balancesByContract: [String: TokenBalance?] = [:]
        let contractAddresses = feeOptions
            .compactMap { normalizedAddress($0.token.contractAddress) }
            .reduce(into: [String]()) { addresses, address in
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }

        for contractAddress in contractAddresses {
            balancesByContract[contractAddress] = await loadTokenBalanceOrZero(
                network: network,
                contractAddress: contractAddress,
                walletAddress: walletAddress
            )
        }

        return feeOptions.map { feeOption in
            let balance: TokenBalance?
            if feeOption.token.isNativeToken {
                balance = nativeBalance
            } else {
                balance = normalizedAddress(feeOption.token.contractAddress)
                    .flatMap { balancesByContract[$0] ?? nil }
            }

            let decimals = feeOption.token.balanceDecimals
            return FeeOptionWithBalance(
                feeOption: feeOption,
                balance: balance,
                available: formatTokenAmount(balance?.balance, decimals: decimals),
                availableRaw: balance?.balance,
                decimals: decimals
            )
        }
    }

    private func loadNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async -> TokenBalance? {
        try? await indexerClient.getNativeTokenBalance(
            network: network,
            walletAddress: walletAddress
        )
    }

    private func loadTokenBalanceOrZero(
        network: Network,
        contractAddress: String,
        walletAddress: String
    ) async -> TokenBalance? {
        do {
            let result = try await indexerClient.getTokenBalances(
                network: network,
                contractAddress: contractAddress,
                walletAddress: walletAddress,
                includeMetadata: false
            )
            return result.balances.first {
                normalizedAddress($0.contractAddress) == contractAddress
            } ?? TokenBalance(
                contractType: "ERC20",
                contractAddress: contractAddress,
                accountAddress: walletAddress,
                tokenId: nil,
                balance: "0",
                blockHash: nil,
                blockNumber: nil,
                chainId: Int64(network.chainId)
            )
        } catch {
            return nil
        }
    }

    private func getExecutedTransactionResult(txnId: String) async throws -> TransactionResult {
        let statusResponse = try await getTransactionStatus(txnId: txnId)

        guard statusResponse.status == .executed else {
            throw TransactionError.transactionFailed(status: statusResponse.status)
        }

        let txnHash = try requireTransactionHash(from: statusResponse)
        return TransactionResult(
            txnId: txnId,
            status: statusResponse.status,
            txnHash: txnHash
        )
    }

    private func requireTransactionHash(from statusResponse: TransactionStatusResponse) throws -> String {
        guard let hash = statusResponse.txnHash else {
            throw TransactionError.missingTransactionHash
        }

        return hash
    }

    private static func makeSignedClient(
        projectAccessKey: String,
        projectId: String,
        environment: OMSClientEnvironment,
        signer: any CredentialSigner
    ) -> WaasWalletClient {
        return WaasWalletClient(
            baseURL: environment.walletApiUrl,
            transport: SignedWaasTransport(
                projectAccessKey: projectAccessKey,
                scope: projectId,
                signer: signer
            ),
            headers: { [:] }
        )
    }

    private static func makePublicClient(
        projectAccessKey: String,
        environment: OMSClientEnvironment
    ) -> WaasWalletPublicClient {
        return WaasWalletPublicClient(
            baseURL: environment.walletApiUrl,
            headers: {
                [
                    "X-Access-Key": projectAccessKey
                ]
            }
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension Array where Element == FeeOption {
    func defaultSelection() -> FeeOptionSelection? {
        first.map { FeeOptionSelection(feeOption: $0) }
    }
}

private extension FeeToken {
    var isNativeToken: Bool {
        type.caseInsensitiveCompare("native") == .orderedSame
            || ((contractAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && (tokenId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }

    var balanceDecimals: Int? {
        decimals.map(Int.init) ?? (isNativeToken ? 18 : nil)
    }
}

private func normalizedAddress(_ address: String?) -> String? {
    guard let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed.lowercased()
}

private func formatTokenAmount(_ value: String?, decimals: Int?) -> String? {
    guard let value else { return nil }
    guard let decimals else { return value }
    return (try? formatUnits(value: value, decimals: decimals)) ?? value
}
