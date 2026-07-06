import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method ensures a request-signing credential exists and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `completeEmailAuth(code:walletSelection:walletType:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func startEmailAuth(email: String) async throws {
        try await runOMSWalletOperation(.walletStartEmailAuth) {
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
    }

    /// Completes the email OTP authentication flow.
    ///
    /// With `.automatic`, this selects the first existing wallet matching `walletType`,
    /// or creates one when none exists. With `.manual`, this verifies auth and returns
    /// a `PendingWalletSelection` so the app can select or create a wallet later.
    @discardableResult
    public func completeEmailAuth(
        code: String,
        walletSelection: WalletSelectionBehavior = .automatic,
        walletType: WalletType = WalletType.ethereum,
        sessionLifetimeSeconds: UInt32 = 604_800
    ) async throws -> CompleteAuthResult {
        try await runOMSWalletOperation(.walletCompleteEmailAuth) {
            let validatedSessionLifetimeSeconds = try requireWaasSessionLifetimeSeconds(sessionLifetimeSeconds)
            let authRevision = sessionRevisionSnapshot()
            let response = try await confirmEmailSignIn(
                code: code,
                sessionLifetimeSeconds: validatedSessionLifetimeSeconds
            )
            return try await completeWalletAuth(
                response,
                walletType: walletType,
                walletSelection: walletSelection,
                sessionAuth: .email(OMSWalletEmailSessionAuth(email: response.email)),
                requiredSessionRevision: authRevision
            )
        }
    }

    /// Signs in with an OIDC ID token.
    ///
    /// With `.automatic`, this selects the first existing wallet matching `walletType`,
    /// or creates one when none exists. With `.manual`, this verifies auth and returns
    /// a `PendingWalletSelection` so the app can select or create a wallet later.
    @discardableResult
    public func signInWithOidcIdToken(
        idToken: String,
        issuer: String,
        audience: String,
        walletType: WalletType = WalletType.ethereum,
        walletSelection: WalletSelectionBehavior = .automatic,
        sessionLifetimeSeconds: UInt32 = 604_800,
        provider: String? = nil,
        providerLabel: String? = nil
    ) async throws -> CompleteAuthResult {
        try await runOMSWalletOperation(.walletSignInWithOidcIdToken) {
            let validatedSessionLifetimeSeconds = try requireWaasSessionLifetimeSeconds(sessionLifetimeSeconds)
            try clearSession(clearOidcRedirectAuth: true)
            let authRevision = sessionRevisionSnapshot()

            do {
                let expiresAt = try OidcIdToken.expiresAtEpochSeconds(idToken)
                let response = try await signedClient.commitVerifier(
                    CommitVerifierRequest(
                        identityType: .oidc,
                        authMode: .idToken,
                        metadata: [
                            "iss": issuer,
                            "aud": audience,
                            "exp": String(expiresAt)
                        ],
                        handle: OidcIdToken.handleHash(idToken)
                    )
                )

                verifier = response.verifier
                challenge = response.challenge

                let auth = try await confirmOidcIdTokenSignIn(
                    idToken: idToken,
                    sessionLifetimeSeconds: validatedSessionLifetimeSeconds
                )
                return try await completeWalletAuth(
                    auth,
                    walletType: walletType,
                    walletSelection: walletSelection,
                    sessionAuth: oidcIdTokenSessionAuth(
                        issuer: issuer,
                        provider: provider,
                        providerLabel: providerLabel,
                        response: auth
                    ),
                    requiredSessionRevision: authRevision
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                try? signOut()
                throw error
            }
        }
    }

    /// Starts OIDC authorization-code redirect authentication.
    ///
    /// Open the returned `authorizationUrl` in a browser or `ASWebAuthenticationSession`.
    /// After the provider redirects back to your app, pass the callback URL to
    /// `handleOidcRedirectCallback(_:walletSelection:sessionLifetimeSeconds:)`.
    public func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String,
        walletType: WalletType = WalletType.ethereum,
        loginHint: String? = nil,
        authorizeParams: [String: String] = [:],
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> StartOidcRedirectAuthResult {
        try await runOMSWalletOperation(.walletStartOidcRedirectAuth) {
            try await startOidcRedirectAuth(
                provider: provider,
                redirectUri: redirectUri,
                walletType: walletType,
                relayRedirectUri: provider.relayRedirectUri ?? derivedRelayRedirectUri(for: provider),
                loginHint: loginHint,
                authorizeParams: authorizeParams,
                walletSelection: walletSelection,
                sessionLifetimeSeconds: sessionLifetimeSeconds
            )
        }
    }

    /// Starts OIDC authorization-code redirect authentication with an explicit
    /// OAuth redirect URI override. Pass `nil` to use the app callback URI directly
    /// even when the provider configuration has a relay redirect URI.
    public func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String,
        walletType: WalletType = WalletType.ethereum,
        relayRedirectUri: String?,
        loginHint: String? = nil,
        authorizeParams: [String: String] = [:],
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> StartOidcRedirectAuthResult {
        try await runOMSWalletOperation(.walletStartOidcRedirectAuth) {
            let requestedSessionLifetimeSeconds = try sessionLifetimeSeconds.map(requireWaasSessionLifetimeSeconds)
            let previousSessionEmail = reauthenticationSessionEmail()
            try clearSession(clearOidcRedirectAuth: true)
            let authRevision = sessionRevisionSnapshot()

            do {
                let signerCredentialId = try credentialSession.signer.credentialId()
                let oauthRedirectUri = relayRedirectUri ?? redirectUri
                let authMode = provider.authMode
                let response = try await signedClient.commitVerifier(
                    CommitVerifierRequest(
                        identityType: .oidc,
                        authMode: authMode.waasAuthMode,
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
                do {
                    try oidcRedirectAuthStore.save(
                        PendingOidcRedirectAuth(
                            verifier: response.verifier,
                            challenge: response.challenge,
                            nonce: nonce,
                            authMode: authMode,
                            redirectUri: redirectUri,
                            issuer: provider.issuer,
                            provider: provider.provider ?? builtInOidcProvider(for: provider.issuer),
                            providerLabel: provider.providerLabel ?? builtInOidcProviderLabel(for: provider.issuer),
                            authorizationScope: self.projectId,
                            walletType: walletType,
                            walletSelection: walletSelection,
                            sessionLifetimeSeconds: requestedSessionLifetimeSeconds,
                            signerCredentialId: signerCredentialId,
                            signerKeyType: credentialSession.signer.alg
                        )
                    )
                } catch {
                    throw OMSWalletError.storageError(
                        message: "OIDC redirect auth state persistence failed.",
                        underlyingError: error
                    )
                }

                try requireCurrentSessionRevision(authRevision)

                let authorizationUrl = try OidcRedirectAuth.buildAuthorizationUrl(
                    provider: provider,
                    redirectUri: oauthRedirectUri,
                    state: state,
                    challenge: response.challenge,
                    loginHint: loginHintForProvider(
                        provider,
                        loginHint: loginHint ?? previousSessionEmail
                    ),
                    authMode: authMode,
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
    }

    /// Safely handles an incoming OIDC authorization-code redirect callback.
    ///
    /// This method is idempotent and safe to call for every incoming app link.
    /// Unrelated links return `.notOidcRedirectCallback`, stale callbacks return
    /// `.noPendingAuth`, and successful auth returns `.completed` or
    /// `.walletSelection` when the resolved wallet selection behavior is `.manual`.
    public func handleOidcRedirectCallback(
        _ callbackUrl: String?,
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> OidcRedirectAuthResult {
        try await runOMSWalletOperation(.walletHandleOidcRedirectCallback) {
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
                return .failed(
                    OMSWalletError.storageError(
                        message: "OIDC redirect auth state restore failed.",
                        operation: .walletHandleOidcRedirectCallback,
                        underlyingError: error
                    )
                )
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
                let authRevision = sessionRevisionSnapshot()
                let resolvedWalletSelection = walletSelection ?? pending.walletSelection ?? .automatic
                let resolvedSessionLifetimeSeconds = try requireWaasSessionLifetimeSeconds(
                    sessionLifetimeSeconds ?? pending.sessionLifetimeSeconds ?? defaultWaasSessionLifetimeSeconds
                )
                let response = try await signedClient.completeAuth(
                    CompleteAuthRequest(
                        identityType: .oidc,
                        authMode: pending.authMode.waasAuthMode,
                        verifier: pending.verifier,
                        answer: code,
                        lifetime: resolvedSessionLifetimeSeconds
                    )
                )
                let result = try await completeWalletAuth(
                    response,
                    walletType: pending.walletType,
                    walletSelection: resolvedWalletSelection,
                    sessionAuth: oidcRedirectSessionAuth(
                        pending: pending,
                        response: response
                    ),
                    requiredSessionRevision: authRevision
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
                return .failed(toOMSWalletError(error, operation: .walletHandleOidcRedirectCallback))
            }
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

    private func loginHintForProvider(
        _ provider: OidcProviderConfig,
        loginHint: String?
    ) -> String? {
        provider.issuer == "https://accounts.google.com" ? loginHint : nil
    }

    private func derivedRelayRedirectUri(for provider: OidcProviderConfig) -> String? {
        let relayProvider = provider.provider ?? builtInOidcProvider(for: provider.issuer)
        guard let relayProvider, relayProvider == "google" || relayProvider == "apple" else {
            return nil
        }
        return "\(environment.walletApiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/auth/waas/callback/\(relayProvider)"
    }

    private func oidcIdTokenSessionAuth(
        issuer: String,
        provider: String?,
        providerLabel: String?,
        response: CompleteAuthResponse
    ) -> OMSWalletSessionAuth {
        let resolvedIssuer = nonEmpty(response.identity.iss) ?? issuer
        return .oidc(
            OMSWalletOidcSessionAuth(
                flow: .idToken,
                issuer: resolvedIssuer,
                provider: provider ?? builtInOidcProvider(for: resolvedIssuer),
                providerLabel: providerLabel ?? builtInOidcProviderLabel(for: resolvedIssuer),
                email: response.email
            )
        )
    }

    private func oidcRedirectSessionAuth(
        pending: PendingOidcRedirectAuth,
        response: CompleteAuthResponse
    ) -> OMSWalletSessionAuth {
        let resolvedIssuer = nonEmpty(response.identity.iss) ?? pending.issuer
        return .oidc(
            OMSWalletOidcSessionAuth(
                flow: .redirect,
                issuer: resolvedIssuer,
                provider: pending.provider ?? builtInOidcProvider(for: resolvedIssuer),
                providerLabel: pending.providerLabel ?? builtInOidcProviderLabel(for: resolvedIssuer),
                email: response.email
            )
        )
    }

    private func builtInOidcProvider(for issuer: String) -> String? {
        switch issuer {
        case "https://accounts.google.com":
            return "google"
        case "https://appleid.apple.com":
            return "apple"
        default:
            return nil
        }
    }

    private func builtInOidcProviderLabel(for issuer: String) -> String? {
        switch issuer {
        case "https://accounts.google.com":
            return "Google"
        case "https://appleid.apple.com":
            return "Apple"
        default:
            return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func confirmEmailSignIn(
        code: String,
        sessionLifetimeSeconds: UInt32
    ) async throws -> CompleteAuthResponse {
        guard !verifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !challenge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OMSWalletError.sessionMissing()
        }

        let answer = RequestUtils.hashEmailAuthAnswer(challenge: challenge, code: code)

        let params = CompleteAuthRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            verifier: verifier,
            answer: answer,
            lifetime: sessionLifetimeSeconds
        )

        return try await signedClient.completeAuth(params)
    }

    private func confirmOidcIdTokenSignIn(
        idToken: String,
        sessionLifetimeSeconds: UInt32
    ) async throws -> CompleteAuthResponse {
        let params = CompleteAuthRequest(
            identityType: IdentityType.oidc,
            authMode: AuthMode.idToken,
            verifier: verifier,
            answer: idToken,
            lifetime: sessionLifetimeSeconds
        )

        return try await signedClient.completeAuth(params)
    }

    private func completeWalletAuth(
        _ response: CompleteAuthResponse,
        walletType: WalletType,
        walletSelection: WalletSelectionBehavior,
        sessionAuth: OMSWalletSessionAuth,
        requiredSessionRevision: UInt64
    ) async throws -> CompleteAuthResult {
        try requireCurrentSessionRevision(requiredSessionRevision)
        activePendingWalletSelection = nil

        let sessionMetadata = SessionMetadata(
            expiresAt: response.credential.expiresAt,
            auth: sessionAuth
        )
        try withSessionLock {
            try requireCurrentSessionRevisionLocked(requiredSessionRevision)
            self.sessionExpiresAt = sessionMetadata.expiresAt
            self.sessionAuth = sessionMetadata.auth
        }

        let wallets = try await signOutOnFailure {
            try await walletsFromAuthResponse(response)
        }
        try requireCurrentSessionRevision(requiredSessionRevision)

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
                    sessionMetadata: sessionMetadata,
                    requiredSessionRevision: requiredSessionRevision
                )
            }
        } else {
            activated = try await signOutOnFailure {
                try await createWallet(
                    walletType: walletType,
                    sessionMetadata: sessionMetadata,
                    requiredSessionRevision: requiredSessionRevision
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
                let selectionRevision = self.sessionRevisionSnapshot()
                let result = try await self.useWallet(
                    walletId: walletId,
                    sessionMetadata: selectionSession.metadata,
                    requiredSessionRevision: selectionRevision
                )
                self.activePendingWalletSelection = nil
                return result
            },
            createAndSelectWalletAction: { reference in
                try self.requireActivePendingWalletSelection(selectionSession)
                let selectionRevision = self.sessionRevisionSnapshot()
                let result = try await self.createWallet(
                    walletType: walletType,
                    reference: reference,
                    sessionMetadata: selectionSession.metadata,
                    requiredSessionRevision: selectionRevision
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
            throw OMSWalletError.walletSelectionStale()
        }
        let selectionSessionState = OMSWalletSessionState(
            walletAddress: nil,
            expiresAtString: selectionSession.metadata.expiresAt,
            auth: selectionSession.metadata.auth
        )
        guard !isSessionExpired(selectionSessionState) else {
            expireSession(selectionSessionState)
            throw OMSWalletError.sessionExpired()
        }
        try requireActiveCredential()
        let signerCredentialId = try credentialSession.signer.credentialId()
        guard signerCredentialId.lowercased() == selectionSession.signerCredentialId.lowercased(),
              credentialSession.signer.alg == selectionSession.signerKeyType else {
            throw OMSWalletError.walletSelectionStale()
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
        try await runOMSWalletOperation(.walletUseWallet) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            let activationRevision = sessionRevisionSnapshot()
            return try await useWallet(
                walletId: walletId,
                sessionMetadata: try currentSessionMetadata(),
                requiredSessionRevision: activationRevision
            )
        }
    }

    /// Creates a new wallet of the specified type for the authenticated user and persists
    /// its address and signer metadata to the keychain.
    ///
    /// Call this after `completeEmailAuth(code:walletSelection:walletType:)` returns
    /// `.walletSelection`, or when an authenticated session already exists.
    ///
    /// - Parameter walletType: The wallet type to create (e.g. `.ethereumEoa`).
    @discardableResult
    public func createWallet(
        walletType: WalletType = WalletType.ethereum,
        reference: String? = nil
    ) async throws -> WalletActivationResult {
        try await runOMSWalletOperation(.walletCreateWallet) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            let activationRevision = sessionRevisionSnapshot()
            return try await createWallet(
                walletType: walletType,
                reference: reference,
                sessionMetadata: try currentSessionMetadata(),
                requiredSessionRevision: activationRevision
            )
        }
    }

    /// Lists all wallets available to the authenticated credential.
    public func listWallets() async throws -> [Wallet] {
        try await runOMSWalletOperation(.walletListWallets) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            return try await listWallets(startingAt: nil)
        }
    }

    private func createWallet(
        walletType: WalletType,
        reference: String? = nil,
        sessionMetadata: SessionMetadata,
        requiredSessionRevision: UInt64
    ) async throws -> WalletActivationResult {
        let params = CreateWalletRequest(
            type: walletType,
            reference: reference
        )

        let response = try await signedClient.createWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata,
            requiredSessionRevision: requiredSessionRevision
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
    private func useWallet(
        walletId: String,
        sessionMetadata: SessionMetadata,
        requiredSessionRevision: UInt64
    ) async throws -> WalletActivationResult {
        let params = UseWalletRequest(
            walletId: walletId
        )

        let response = try await signedClient.useWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata,
            requiredSessionRevision: requiredSessionRevision
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

}

private let defaultWaasSessionLifetimeSeconds: UInt32 = 604_800
private let maxWaasSessionLifetimeSeconds: UInt32 = 2_592_000

private func requireWaasSessionLifetimeSeconds(_ sessionLifetimeSeconds: UInt32) throws -> UInt32 {
    guard sessionLifetimeSeconds >= 1 && sessionLifetimeSeconds <= maxWaasSessionLifetimeSeconds else {
        throw OMSWalletError(
            code: .validationError,
            message: "sessionLifetimeSeconds must be an integer between 1 and \(maxWaasSessionLifetimeSeconds)"
        )
    }
    return sessionLifetimeSeconds
}
