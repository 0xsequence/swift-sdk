public enum TransactionError: Error {
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}

@available(macOS 12.0, iOS 15.0, *)
public class WalletClient {
    var signedClient: WaasWalletClient
    let keychain: KeychainManager = KeychainManager()
    
    public var walletAddress: String
    public var walletId: String
    
    var sessionPrivateKey: [UInt8]
    
    var verifier = "";
    var challenge = "";
    
    public init(projectAccessKey: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        if let walletAddress = try? keychain.string(forKey: Constants.addressStorageKey),
           let walletId = try? keychain.string(forKey: Constants.walletIdStorageKey),
           let signerPrivateKeyHex = try? keychain.string(forKey: Constants.signerStorageKey) {
            self.walletAddress = walletAddress
            self.walletId = walletId
            self.sessionPrivateKey = ByteUtils.hexToBytes(hex: signerPrivateKeyHex)
        } else {
            self.walletAddress = ""
            self.walletId = ""
            self.sessionPrivateKey = try! EthereumSigner.GeneratePrivateKey()
        }

        self.signedClient = WaasWalletClient(
            baseURL: environment.walletApiUrl,
            transport: SignedWaasTransport(
                projectAccessKey: projectAccessKey,
                privateKey: sessionPrivateKey
            ),
            headers: { [:] }
        )
    }
    
    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method generates a new session key pair and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `completeEmailSignIn(code:walletType:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func startEmailAuth(email: String) async {
        let params = CommitVerifierRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            metadata: [String : String] (),
            handle: email
        )
        
        let response = try! await signedClient.commitVerifier(params)

        verifier = response.verifier
        challenge = response.challenge
    }
    
    /// Completes the email OTP authentication flow by verifying the code the user received.
    ///
    /// Must be called after `signInWithEmail(email:)`. The challenge and verifier from the
    /// previous step are used automatically. On success, this method also provisions a wallet
    /// of `walletType` for the authenticated user: if one already exists on the account it is
    /// loaded, otherwise a new one is created. In both cases the wallet address and session key
    /// are persisted to the keychain.
    ///
    /// - Parameters:
    ///   - code: The one-time passcode string entered by the user.
    ///   - walletType: The wallet type to load or create for this user. Defaults to `.ethereumEoa`.
    public func completeEmailAuth(code: String, walletType: WalletType = WalletType.ethereum) async {
        let answer = RequestUtils.hashEmailAuthAnswer(challenge: challenge, code: code)

        let params = CompleteAuthRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            verifier: verifier,
            answer: answer,
        )
        
        let response = try! await signedClient.completeAuth(params)
        
        var walletUsed: Bool = false;
        for wallet in response.wallets {
            if (wallet.type == walletType) {
                await useWallet(walletId: wallet.id)
                walletUsed = true
            }
        }
        
        if (!walletUsed) {
            await createWallet(walletType: walletType)
        }
    }
    
    /// Creates a new wallet of the specified type for the authenticated user and persists
    /// its address and session key to the keychain.
    ///
    /// Called internally by `completeEmailSignIn(code:walletType:)` when the user does not
    /// already have a wallet of the requested type.
    ///
    /// - Parameter walletType: The wallet type to create (e.g. `.ethereumEoa`).
    private func createWallet(walletType: WalletType) async {
        let params = CreateWalletRequest(
            type: walletType
        )
        
        let response = try! await signedClient.createWallet(params)
        createSequenceWallet(walletAddress: response.wallet.address, walletId: response.wallet.id);
    }
    
    /// Loads an existing wallet of the specified type for the authenticated user and persists
    /// its address and session key to the keychain.
    ///
    /// Called internally by `completeEmailSignIn(code:walletType:)` when the user already has
    /// a wallet of the requested type on their account.
    ///
    /// - Parameter walletType: The wallet type to load (e.g. `.ethereumEoa`).
    private func useWallet(walletId: String) async {
        let params = UseWalletRequest(
            walletId: walletId
        )
        
        let response = try! await signedClient.useWallet(params)
        createSequenceWallet(walletAddress: response.wallet.address, walletId: response.wallet.id);
    }
    
    /// Persists the given wallet address and the current session private key to the keychain
    /// so the session can be restored on a later launch.
    ///
    /// - Parameter address: The on-chain address returned by `createWallet` or `useWallet`.
    private func createSequenceWallet(walletAddress: String, walletId: String) {
        self.walletAddress = walletAddress
        self.walletId = walletId
        
        try! keychain.set(walletAddress, forKey: Constants.addressStorageKey)
        try! keychain.set(walletId, forKey: Constants.walletIdStorageKey)
        try! keychain.set(ByteUtils.bytesToHex(data: self.sessionPrivateKey), forKey: Constants.signerStorageKey)
    }
    
    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, any attempt to restore the session on the next launch will fail
    /// and the user will need to sign in again via `signInWithEmail(email:)`. Navigate to your
    /// sign-in screen after calling this.
    public func signOut() {
        let keychain: KeychainManager = KeychainManager()
        try! keychain.delete(forKey: Constants.addressStorageKey)
        try! keychain.delete(forKey: Constants.signerStorageKey)
    }
    
    /// Returns a list of credentials that currently have access to this wallet.
    ///
    /// Use this to display active sessions or integrations in your app's account
    /// management UI, or to check what credentials exist before revoking one.
    ///
    /// - Returns: An array of `CredentialInfo` values representing each credential
    ///   with access to this wallet.
    public func listAccess() async -> [CredentialInfo] {
        let params = ListAccessRequest(
            walletId: self.walletId
        )
        
        let response = try! await signedClient.listAccess(params)
        return response.credentials
    }

    /// Revokes access for a specific credential, preventing it from interacting
    /// with this wallet going forward.
    ///
    /// Use `listAccess()` first to retrieve the credential IDs available to revoke.
    /// This action cannot be undone — the credential will need to be re-authorized
    /// to regain access.
    ///
    /// - Parameter targetCredentialId: The unique identifier of the credential to revoke.
    public func revokeAccess(targetCredentialId: String) async {
        let params = RevokeAccessRequest(
            targetCredentialId: targetCredentialId,
            walletId: self.walletId
        )
        
        try! await signedClient.revokeAccess(params)
    }
    
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: String, message: String) async -> String {
        let params = SignMessageRequest(
            network: network,
            walletId: self.walletId,
            message: message
        )
        
        let response = try! await signedClient.signMessage(params)
        return response.signature
    }

    public func sendTransaction(network: String, to: String, value: String) async throws -> String {
        return try await self.sendTransaction(network: network, request: SendTransactionRequest(
            to: to,
            value: value,
            data: nil,
            feeCeiling: nil,
            nonce: nil
        ))
    }

    public func sendTransaction(
        network: String,
        request: SendTransactionRequest
    ) async throws -> String {
        let prepareResponse = try await signedClient.prepareEthereumTransaction(
            PrepareEthereumTransactionRequest(
                network: network,
                walletId: self.walletId,
                to: request.to,
                value: request.value,
                data: nil,
                mode: .relayer
            )
        )
        
        return try await self.execute(txnId: prepareResponse.txnId);
    }
    
    public func callContract(
        network: String,
        contract: String,
        method: String,
        args: [AbiArg]?
    ) async throws -> String {
        let prepareResponse = try await signedClient.prepareContractCall(
            PrepareContractCallRequest(
                network: network,
                walletId: self.walletId,
                contract: contract,
                method: method,
                args: args,
                mode: .relayer
            )
        )

        return try await self.execute(txnId: prepareResponse.txnId);
    }
    
    private func execute(txnId: String) async throws -> String {
        let executeResponse = try await signedClient.execute(
            ExecuteRequest(txnId: txnId, feeOption: nil)
        )
        var status = executeResponse.status

        let pollIntervalNanos: UInt64 = 750_000_000
        let maxAttempts = 10  // ~45s ceiling
        var attempts = 0

        while status == .pending {
            guard attempts < maxAttempts else {
                throw TransactionError.pollingTimedOut
            }
            try await Task.sleep(nanoseconds: pollIntervalNanos)
            attempts += 1

            let statusResponse = try await signedClient.getTransactionStatus(
                GetTransactionStatusRequest(txnId: txnId)
            )
            status = statusResponse.status

            if status == .executed {
                guard let hash = statusResponse.txnHash else {
                    throw TransactionError.missingTransactionHash
                }
                return hash
            }
        }

        // Loop exited without `.executed` — surface the terminal status.
        throw TransactionError.transactionFailed(status: status)
    }
}
