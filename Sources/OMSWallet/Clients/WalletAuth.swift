import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method ensures a request-signing credential exists and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `completeEmailAuth(code:walletSelection:walletType:)`.
    ///
    /// - Parameters:
    ///   - email: The email address to send the one-time passcode to.
    ///   - sessionLifetimeSeconds: The requested credential lifetime. Must be from 1 through
    ///     2,592,000 seconds (30 days).
    public func startEmailAuth(
        email: String,
        sessionLifetimeSeconds: UInt32 = 604_800
    ) async throws {
        try await runOMSWalletOperation(.walletStartEmailAuth) {
            let validatedSessionLifetimeSeconds = try requireWaasSessionLifetimeSeconds(sessionLifetimeSeconds)
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
                pendingEmailAuth = PendingEmailAuth(
                    email: email,
                    sessionLifetimeSeconds: validatedSessionLifetimeSeconds
                )
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
        walletType: WalletType = WalletType.ethereum
    ) async throws -> CompleteAuthResult {
        try await runOMSWalletOperation(.walletCompleteEmailAuth) {
            guard let pendingEmailAuth else {
                throw OMSWalletError.sessionMissing()
            }
            let authRevision = sessionRevisionSnapshot()
            let response = try await confirmEmailSignIn(
                code: code,
                sessionLifetimeSeconds: pendingEmailAuth.sessionLifetimeSeconds
            )
            return try await completeWalletAuth(
                response,
                walletType: walletType,
                walletSelection: walletSelection,
                sessionAuth: .email(OMSWalletEmailSessionAuth(email: response.email ?? pendingEmailAuth.email)),
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
    /// Open the returned `authorizationURL` in a browser or `ASWebAuthenticationSession`.
    /// After the provider redirects back to the configured provider redirect URI, pass the callback URL to
    /// `handleOIDCRedirectCallback(_:walletSelection:sessionLifetimeSeconds:)`.
    public func startOIDCRedirectAuth(
        provider: CustomOIDCProviderConfiguration,
        walletType: WalletType = WalletType.ethereum,
        loginHint: String? = nil,
        authorizeParams: [String: String] = [:],
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> StartOIDCRedirectAuthResult {
        try await runOMSWalletOperation(.walletStartOIDCRedirectAuth) {
            guard !provider.providerRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OIDCRedirectAuthError.missingProviderRedirectURI
            }
            return try await startOIDCRedirectAuth(
                provider: provider.resolvedConfiguration,
                providerRedirectURI: provider.providerRedirectURI,
                expectedCallbackURI: provider.providerRedirectURI,
                stateRedirectURI: nil,
                walletType: walletType,
                loginHint: loginHint,
                authorizeParams: authorizeParams,
                walletSelection: walletSelection,
                sessionLifetimeSeconds: sessionLifetimeSeconds
            )
        }
    }

    /// Starts OIDC authorization-code redirect authentication through the built-in
    /// OMS relay for the fixed Google and Apple provider values.
    public func startOIDCRedirectAuth(
        provider: OMSRelayOIDCProvider,
        omsRelayReturnURI: String,
        walletType: WalletType = WalletType.ethereum,
        loginHint: String? = nil,
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> StartOIDCRedirectAuthResult {
        try await runOMSWalletOperation(.walletStartOIDCRedirectAuth) {
            guard !omsRelayReturnURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OIDCRedirectAuthError.missingOMSRelayReturnURI
            }
            let providerRedirectURI = derivedRelayRedirectURI(for: provider.relayPathComponent)
            return try await startOIDCRedirectAuth(
                provider: provider.resolvedConfiguration,
                providerRedirectURI: providerRedirectURI,
                expectedCallbackURI: omsRelayReturnURI,
                stateRedirectURI: omsRelayReturnURI,
                walletType: walletType,
                loginHint: loginHint,
                authorizeParams: [:],
                walletSelection: walletSelection,
                sessionLifetimeSeconds: sessionLifetimeSeconds
            )
        }
    }

    private func startOIDCRedirectAuth(
        provider: ResolvedOIDCProviderConfiguration,
        providerRedirectURI: String,
        expectedCallbackURI: String,
        stateRedirectURI: String?,
        walletType: WalletType,
        loginHint: String?,
        authorizeParams: [String: String],
        walletSelection: WalletSelectionBehavior?,
        sessionLifetimeSeconds: UInt32?
    ) async throws -> StartOIDCRedirectAuthResult {
        let requestedSessionLifetimeSeconds = try sessionLifetimeSeconds.map(requireWaasSessionLifetimeSeconds)
        let previousSessionEmail = reauthenticationSessionEmail()
        try clearSession(clearOidcRedirectAuth: true)
        let authRevision = sessionRevisionSnapshot()
        var pendingAuth: PendingOIDCRedirectAuth?

        do {
            let signerCredentialId = try credentialSession.signer.credentialId()
            let authMode = provider.authMode
            let response = try await signedClient.commitVerifier(
                CommitVerifierRequest(
                    identityType: .oidc,
                    authMode: authMode.waasAuthMode,
                    metadata: [
                        "iss": provider.issuer,
                        "aud": provider.clientID,
                        "redirect_uri": providerRedirectURI
                    ]
                )
            )
            let nonce = try oidcNonceGenerator()
            let state = try OIDCRedirectAuth.encodeState(
                nonce: nonce,
                scope: projectId,
                redirectUri: stateRedirectURI
            )

            verifier = response.verifier
            challenge = response.challenge
            let pending = PendingOIDCRedirectAuth(
                verifier: response.verifier,
                challenge: response.challenge,
                nonce: nonce,
                authMode: authMode,
                redirectUri: expectedCallbackURI,
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
            pendingAuth = pending
            do {
                try saveNewPendingOIDCRedirectAuth(
                    pending,
                    requiredSessionRevision: authRevision
                )
            } catch let error as OMSWalletError {
                throw error
            } catch {
                throw OMSWalletError.storageError(
                    message: "OIDC redirect auth state persistence failed.",
                    underlyingError: error
                )
            }

            try requireCurrentSessionRevision(authRevision)

            let authorizationURL = try OIDCRedirectAuth.buildAuthorizationURL(
                provider: provider,
                redirectURI: providerRedirectURI,
                state: state,
                challenge: response.challenge,
                loginHint: loginHintForProvider(
                    provider,
                    loginHint: loginHint ?? previousSessionEmail
                ),
                authMode: authMode,
                authorizeParams: provider.authorizeParams.merging(authorizeParams) { _, new in new }
            )
            try requireCurrentSessionRevision(authRevision)

            return StartOIDCRedirectAuthResult(authorizationURL: authorizationURL)
        } catch {
            if let pendingAuth {
                clearPendingOIDCRedirectAuthBestEffort(pendingAuth)
            }
            _ = try? clearSession(
                clearOidcRedirectAuth: false,
                requiredSessionRevision: authRevision
            )
            throw error
        }
    }

    /// Safely handles an incoming OIDC authorization-code redirect callback.
    ///
    /// This method is idempotent and safe to call for every incoming app link.
    /// Unrelated links return `.notOIDCRedirectCallback`, callbacks with no pending
    /// or already consumed flow return `.noPendingAuth`, and successful auth returns
    /// `.completed`. Lost flow ownership throws a normalized error.
    public func handleOIDCRedirectCallback(
        _ callbackURL: String?,
        walletSelection: WalletSelectionBehavior? = nil,
        sessionLifetimeSeconds: UInt32? = nil
    ) async throws -> OIDCRedirectAuthResult {
        try await runOMSWalletOperation(.walletHandleOIDCRedirectCallback) {
            guard let callbackURL = callbackURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !callbackURL.isEmpty else {
                return .notOIDCRedirectCallback
            }

            let callback = OIDCRedirectAuth.parseCallbackURL(callbackURL)
            guard callback.hasOidcResponse else {
                return .notOIDCRedirectCallback
            }

            let pending: PendingOIDCRedirectAuth
            do {
                guard let loaded = try loadPendingOIDCRedirectAuth() else {
                    return .noPendingAuth
                }
                pending = loaded
            } catch {
                throw OMSWalletError.storageError(
                    message: "OIDC redirect auth state restore failed.",
                    operation: .walletHandleOIDCRedirectCallback,
                    underlyingError: error
                )
            }

            guard OIDCRedirectAuth.matchesRedirectURI(
                callbackURL: callbackURL,
                redirectURI: pending.redirectUri
            ) else {
                return .notOIDCRedirectCallback
            }

            guard let state = callback.state,
                  (try? OIDCRedirectAuth.validateState(state, pending: pending)) != nil else {
                return .notOIDCRedirectCallback
            }
            let consumed: Bool
            do {
                consumed = try consumeOIDCRedirectAuth(pending)
            } catch {
                throw OMSWalletError.storageError(
                    message: "OIDC redirect auth state consumption failed.",
                    operation: .walletHandleOIDCRedirectCallback,
                    underlyingError: error
                )
            }
            guard consumed else {
                return .noPendingAuth
            }
            let callbackSessionRevision = sessionRevisionSnapshot()

            let result: CompleteAuthResult
            do {
                if let error = callback.error {
                    throw OIDCRedirectAuthError.providerError(
                        callback.errorDescription ?? "OIDC provider returned error: \(error)"
                    )
                }
                guard let code = callback.code else {
                    throw OIDCRedirectAuthError.missingCode
                }

                try restorePendingOIDCRedirectAuth(
                    pending,
                    requiredSessionRevision: callbackSessionRevision
                )
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
                result = try await completeWalletAuth(
                    response,
                    walletType: pending.walletType,
                    walletSelection: resolvedWalletSelection,
                    sessionAuth: oidcRedirectSessionAuth(
                        pending: pending,
                        response: response
                    ),
                    requiredSessionRevision: callbackSessionRevision,
                    oidcRedirectAuthOwnership: pending
                )
            } catch let error as CancellationError {
                try? withOIDCRedirectAuthOwnership(pending) {
                    _ = try clearSession(
                        clearOidcRedirectAuth: false,
                        requiredSessionRevision: callbackSessionRevision
                    )
                }
                clearPendingOIDCRedirectAuthBestEffort(pending)
                throw error
            } catch {
                let failure = toOMSWalletError(error, operation: .walletHandleOIDCRedirectCallback)
                try? withOIDCRedirectAuthOwnership(pending) {
                    _ = try clearSession(
                        clearOidcRedirectAuth: false,
                        requiredSessionRevision: callbackSessionRevision
                    )
                }
                clearPendingOIDCRedirectAuthBestEffort(pending)
                throw failure
            }

            clearPendingOIDCRedirectAuthBestEffort(pending)
            return .completed(result)
        }
    }

    private func restorePendingOIDCRedirectAuth(
        _ pending: PendingOIDCRedirectAuth,
        requiredSessionRevision: UInt64
    ) throws {
        try withOIDCRedirectAuthOwnership(pending) {
            try withSessionLock {
                try requireCurrentSessionRevisionLocked(requiredSessionRevision)
                try requireActiveCredential()
                let signerCredentialId = try credentialSession.signer.credentialId()
                guard signerCredentialId.lowercased() == pending.signerCredentialId.lowercased(),
                      pending.signerKeyType == credentialSession.signer.alg else {
                    throw OIDCRedirectAuthError.signerMismatch
                }

                verifier = pending.verifier
                challenge = pending.challenge
            }
        }
    }

    private func loginHintForProvider(
        _ provider: ResolvedOIDCProviderConfiguration,
        loginHint: String?
    ) -> String? {
        provider.issuer == "https://accounts.google.com" ? loginHint : nil
    }

    private func derivedRelayRedirectURI(for relayProvider: String) -> String {
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
        pending: PendingOIDCRedirectAuth,
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
        requiredSessionRevision: UInt64,
        oidcRedirectAuthOwnership: PendingOIDCRedirectAuth? = nil
    ) async throws -> CompleteAuthResult {
        let sessionMetadata = SessionMetadata(
            expiresAt: response.credential.expiresAt,
            auth: sessionAuth
        )
        try withOptionalOIDCRedirectAuthOwnership(oidcRedirectAuthOwnership) {
            try requireCurrentSessionRevision(requiredSessionRevision)
            activePendingWalletSelection = nil
            try withSessionLock {
                try requireCurrentSessionRevisionLocked(requiredSessionRevision)
                self.sessionExpiresAt = sessionMetadata.expiresAt
                self.sessionAuth = sessionMetadata.auth
            }
        }

        let wallets: [Wallet]
        if oidcRedirectAuthOwnership == nil {
            wallets = try await signOutOnFailure {
                try await walletsFromAuthResponse(response)
            }
        } else {
            wallets = try await walletsFromAuthResponse(response)
        }
        try withOptionalOIDCRedirectAuthOwnership(oidcRedirectAuthOwnership) {
            try requireCurrentSessionRevision(requiredSessionRevision)
        }

        let candidateWallets = wallets.filter { $0.type == walletType }
        guard walletSelection == .automatic else {
            let pendingSelectionSession = try withOptionalOIDCRedirectAuthOwnership(
                oidcRedirectAuthOwnership
            ) {
                try beginPendingWalletSelection(sessionMetadata: sessionMetadata)
            }
            return .walletSelection(
                pendingWalletSelection(
                    walletType: walletType,
                    wallets: candidateWallets,
                    credential: response.credential.sdkValue,
                    selectionSession: pendingSelectionSession
                )
            )
        }

        let activated: WalletSelectionResult
        if let selectedWallet = candidateWallets.first {
            if oidcRedirectAuthOwnership == nil {
                activated = try await signOutOnFailure {
                    try await useWallet(
                        walletId: selectedWallet.id,
                        sessionMetadata: sessionMetadata,
                        requiredSessionRevision: requiredSessionRevision
                    )
                }
            } else {
                activated = try await useWallet(
                    walletId: selectedWallet.id,
                    sessionMetadata: sessionMetadata,
                    requiredSessionRevision: requiredSessionRevision,
                    oidcRedirectAuthOwnership: oidcRedirectAuthOwnership
                )
            }
        } else {
            if oidcRedirectAuthOwnership == nil {
                activated = try await signOutOnFailure {
                    try await createWallet(
                        walletType: walletType,
                        sessionMetadata: sessionMetadata,
                        requiredSessionRevision: requiredSessionRevision
                    )
                }
            } else {
                activated = try await createWallet(
                    walletType: walletType,
                    sessionMetadata: sessionMetadata,
                    requiredSessionRevision: requiredSessionRevision,
                    oidcRedirectAuthOwnership: oidcRedirectAuthOwnership
                )
            }
        }

        return .walletSelected(
            walletAddress: activated.walletAddress,
            wallet: activated.wallet,
            wallets: candidateWallets.isEmpty ? wallets + [activated.wallet] : wallets,
            credential: response.credential.sdkValue
        )
    }

    private func withOptionalOIDCRedirectAuthOwnership<T>(
        _ pending: PendingOIDCRedirectAuth?,
        _ body: () throws -> T
    ) throws -> T {
        if let pending {
            return try withOIDCRedirectAuthOwnership(pending, body)
        }
        return try body()
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
    public func useWallet(walletId: String) async throws -> WalletSelectionResult {
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
    ) async throws -> WalletSelectionResult {
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
        requiredSessionRevision: UInt64,
        oidcRedirectAuthOwnership: PendingOIDCRedirectAuth? = nil
    ) async throws -> WalletSelectionResult {
        let params = CreateWalletRequest(
            type: walletType.waasValue,
            reference: reference
        )

        let response = try await signedClient.createWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata,
            requiredSessionRevision: requiredSessionRevision,
            oidcRedirectAuthOwnership: oidcRedirectAuthOwnership
        )

        return WalletSelectionResult(
            walletAddress: response.wallet.address,
            wallet: response.wallet.sdkValue
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
        requiredSessionRevision: UInt64,
        oidcRedirectAuthOwnership: PendingOIDCRedirectAuth? = nil
    ) async throws -> WalletSelectionResult {
        let params = UseWalletRequest(
            walletId: walletId
        )

        let response = try await signedClient.useWallet(params)
        try createSequenceWallet(
            walletAddress: response.wallet.address,
            walletId: response.wallet.id,
            sessionMetadata: sessionMetadata,
            requiredSessionRevision: requiredSessionRevision,
            oidcRedirectAuthOwnership: oidcRedirectAuthOwnership
        )

        return WalletSelectionResult(
            walletAddress: response.wallet.address,
            wallet: response.wallet.sdkValue
        )
    }

    private func walletsFromAuthResponse(_ response: CompleteAuthResponse) async throws -> [Wallet] {
        var wallets = response.wallets.map { $0.sdkValue }
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
                    page: cursor.map { Page(cursor: $0).waasValue }
                )
            )
            wallets += response.wallets.map { $0.sdkValue }
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
