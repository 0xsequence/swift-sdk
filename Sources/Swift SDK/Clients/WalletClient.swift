public enum TransactionError: Error {
    case noFeeOptionsAvailable
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
        if let credentialsJson = try? keychain.string(forKey: Constants.credentialsStorageKey) {
            let credentials = try! StorableCredentials.from(jsonString: credentialsJson)
            
            self.walletId = credentials.walletId
            self.walletAddress = credentials.walletAddress
            self.sessionPrivateKey = ByteUtils.hexToBytes(hex: credentials.privateKeyHex)
        } else {
            self.walletAddress = ""
            self.walletId = ""
            self.sessionPrivateKey = try! EthereumSigner.GeneratePrivateKey()
        }

        self.signedClient = WaasWalletClient(
            baseURL: environment.walletApiUrl,
            transport: SignedWaasTransport(
                projectAccessKey: projectAccessKey,
                scope: environment.scope,
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
        
        let storableCredentials = StorableCredentials(
            walletId: walletId,
            walletAddress: walletAddress,
            privateKeyHex: ByteUtils.bytesToHex(data: self.sessionPrivateKey)
        )
        
        try! keychain.set(storableCredentials.jsonString(), forKey: Constants.credentialsStorageKey)
    }
    
    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, any attempt to restore the session on the next launch will fail
    /// and the user will need to sign in again via `signInWithEmail(email:)`. Navigate to your
    /// sign-in screen after calling this.
    public func signOut() {
        let keychain: KeychainManager = KeychainManager()
        try! keychain.delete(forKey: Constants.credentialsStorageKey)
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

    public func sendTransaction(
        network: String,
        to: String,
        value: String,
        feeOptionSelector: FeeOptionSelector = .first
    ) async throws -> String {
        return try await self.sendTransaction(network: network, request: SendTransactionRequest(
            to: to,
            value: value,
            data: nil,
            feeCeiling: nil,
            nonce: nil
        ), feeOptionSelector: feeOptionSelector)
    }

    public func sendTransaction(
        network: String,
        request: SendTransactionRequest,
        feeOptionSelector: FeeOptionSelector = .first
    ) async throws -> String {
        let prepareResponse = try await signedClient.prepareEthereumTransaction(
            PrepareEthereumTransactionRequest(
                network: network,
                walletId: self.walletId,
                to: request.to,
                value: request.value,
                data: request.data,
                mode: .relayer
            )
        )
        
        return try await self.execute(
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector
        );
    }
    
    public func callContract(
        network: String,
        contract: String,
        method: String,
        args: [AbiArg]?,
        feeOptionSelector: FeeOptionSelector = .first
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

        return try await self.execute(
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector
        );
    }
    
    private func execute(
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector
    ) async throws -> String {
        var feeOption: FeeOption? = nil
        if !prepareResponse.sponsored {
            feeOption = try await feeOptionSelector.callAsFunction(prepareResponse.feeOptions)
        }
        
        var feeOptionSelection: FeeOptionSelection? = nil
        if feeOption != nil {
            feeOptionSelection = FeeOptionSelection(token: feeOption?.token.tokenId ?? "")
        }
        
        let executeRequest = ExecuteRequest(
            txnId: prepareResponse.txnId,
            feeOption: feeOptionSelection
        )
        
        let executeResponse = try await signedClient.execute(executeRequest)
        var status = executeResponse.status
        if status == .executed {
            return try await getExecutedTransactionHash(txnId: prepareResponse.txnId)
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

            let statusResponse = try await signedClient.getTransactionStatus(
                GetTransactionStatusRequest(txnId: prepareResponse.txnId)
            )
            status = statusResponse.status

            if status == .executed {
                return try requireTransactionHash(from: statusResponse)
            }
        }

        // Loop exited without `.executed` — surface the terminal status.
        throw TransactionError.transactionFailed(status: status)
    }

    private func getExecutedTransactionHash(txnId: String) async throws -> String {
        let statusResponse = try await signedClient.getTransactionStatus(
            GetTransactionStatusRequest(txnId: txnId)
        )

        guard statusResponse.status == .executed else {
            throw TransactionError.transactionFailed(status: statusResponse.status)
        }

        return try requireTransactionHash(from: statusResponse)
    }

    private func requireTransactionHash(from statusResponse: TransactionStatusResponse) throws -> String {
        guard let hash = statusResponse.txnHash else {
            throw TransactionError.missingTransactionHash
        }

        return hash
    }
}
