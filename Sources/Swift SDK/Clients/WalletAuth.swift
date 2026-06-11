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
        try await runOmsOperation(.walletStartEmailAuth) {
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
        try await runOmsOperation(.walletCompleteEmailAuth) {
            let response = try await confirmEmailSignIn(
                code: code,
                sessionLifetimeSeconds: sessionLifetimeSeconds
            )
            return try await completeWalletAuth(
                response,
                walletType: walletType,
                walletSelection: walletSelection
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
        sessionLifetimeSeconds: UInt32 = 604_800
    ) async throws -> CompleteAuthResult {
        try await runOmsOperation(.walletSignInWithOidcIdToken) {
            try clearSession(clearOidcRedirectAuth: true)

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
                    sessionLifetimeSeconds: sessionLifetimeSeconds
                )
                return try await completeWalletAuth(
                    auth,
                    walletType: walletType,
                    walletSelection: walletSelection
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                try? signOut()
                throw error
            }
        }
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
        loginHint: String? = nil,
        authorizeParams: [String: String] = [:]
    ) async throws -> StartOidcRedirectAuthResult {
        try await runOmsOperation(.walletStartOidcRedirectAuth) {
            try await startOidcRedirectAuth(
                provider: provider,
                redirectUri: redirectUri,
                walletType: walletType,
                relayRedirectUri: provider.relayRedirectUri,
                loginHint: loginHint,
                authorizeParams: authorizeParams
            )
        }
    }

    /// Starts OIDC authorization-code PKCE redirect authentication with an explicit
    /// OAuth redirect URI override. Pass `nil` to use the app callback URI directly
    /// even when the provider configuration has a relay redirect URI.
    public func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String,
        walletType: WalletType = WalletType.ethereum,
        relayRedirectUri: String?,
        loginHint: String? = nil,
        authorizeParams: [String: String] = [:]
    ) async throws -> StartOidcRedirectAuthResult {
        try await runOmsOperation(.walletStartOidcRedirectAuth) {
            let previousSessionEmail = reauthenticationSessionEmail()
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
                    loginHint: loginHintForProvider(
                        provider,
                        loginHint: loginHint ?? previousSessionEmail
                    ),
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

    /// Safely handles an incoming OIDC authorization-code PKCE redirect callback.
    ///
    /// This method is idempotent and safe to call for every incoming app link.
    /// Unrelated links return `.notOidcRedirectCallback`, stale callbacks return
    /// `.noPendingAuth`, and successful auth returns `.completed` or
    /// `.walletSelection` when `walletSelection` is `.manual`.
    public func handleOidcRedirectCallback(
        _ callbackUrl: String?,
        walletSelection: WalletSelectionBehavior = .automatic,
        sessionLifetimeSeconds: UInt32 = 604_800
    ) async throws -> OidcRedirectAuthResult {
        try await runOmsOperation(.walletHandleOidcRedirectCallback) {
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
                        lifetime: sessionLifetimeSeconds
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
                return .failed(toOmsSdkError(error, operation: .walletHandleOidcRedirectCallback))
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

    private func confirmEmailSignIn(
        code: String,
        sessionLifetimeSeconds: UInt32
    ) async throws -> CompleteAuthResponse {
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
            throw OmsSdkError.walletSelectionStale()
        }
        let selectionSessionState = SessionState(
            walletAddress: nil,
            expiresAtString: selectionSession.metadata.expiresAt,
            loginType: selectionSession.metadata.loginType,
            sessionEmail: selectionSession.metadata.sessionEmail
        )
        guard !isSessionExpired(selectionSessionState) else {
            expireSession(selectionSessionState)
            throw OmsSdkError.sessionMissing()
        }
        try requireActiveCredential()
        let signerCredentialId = try credentialSession.signer.credentialId()
        guard signerCredentialId.lowercased() == selectionSession.signerCredentialId.lowercased(),
              credentialSession.signer.alg == selectionSession.signerKeyType else {
            throw OmsSdkError.walletSelectionStale()
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
        try await runOmsOperation(.walletUseWallet) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            return try await useWallet(
                walletId: walletId,
                sessionMetadata: currentSessionMetadata()
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
        try await runOmsOperation(.walletCreateWallet) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            return try await createWallet(
                walletType: walletType,
                reference: reference,
                sessionMetadata: currentSessionMetadata()
            )
        }
    }

    /// Lists all wallets available to the authenticated credential.
    public func listWallets() async throws -> [Wallet] {
        try await runOmsOperation(.walletListWallets) {
            try requireWalletSelectionOrActiveSession()
            try requireActiveCredential()
            return try await listWallets(startingAt: nil)
        }
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

}
