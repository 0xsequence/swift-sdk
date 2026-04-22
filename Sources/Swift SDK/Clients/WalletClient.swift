@available(macOS 12.0, iOS 15.0, *)
public class WalletClient {
    var signedClient: WaasWalletClient
    let keychain: KeychainManager = KeychainManager()
    
    public var walletAddress: String
    public var walletId: String
    
    var sessionPrivateKey: [UInt8]
    
    var verifier = "";
    var challenge = "";
    
    public init(projectAccessKey: String, environment: OmsEnvironment = OmsEnvironment()) {
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
    public func signInWithEmail(email: String) async {
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
    public func completeEmailSignIn(code: String, walletType: WalletType = WalletType.ethereum) async {
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
    public func clearSession() {
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
    
    /// Sends a native token transfer to the specified address on the given network.
    ///
    /// The transaction is submitted via the Sequence relayer, so the user does not need
    /// to hold gas tokens to cover fees.
    ///
    /// - Parameters:
    ///   - network: The network to send the transaction on (e.g., `"mainnet"`, `"polygon"`).
    ///   - to: The recipient's wallet address.
    ///   - value: The amount to send, as a string in the network's smallest denomination (e.g., wei for Ethereum).
    /// - Returns: The transaction hash of the submitted transaction.
    public func sendTransaction(network: String, to: String, value: String) async -> String {
        let params = SendTransactionRequest(
            network: network,
            walletId: self.walletId,
            to: to,
            value: value,
            mode: TransactionMode.relayer
        )
        
        let response = try! await signedClient.sendTransaction(params)
        return response.txHash
    }

    /// Calls a smart contract function with the provided parameters.
    ///
    /// Use this for any contract interaction that writes state — token transfers, NFT mints,
    /// approvals, and so on. For read-only calls that don't require a transaction, query the
    /// contract directly without this method.
    ///
    /// - Parameter params: A `CallContractRequest` describing the target contract, function
    ///   selector, ABI-encoded arguments, network, and any value to attach to the call.
    /// - Returns: The transaction hash of the submitted transaction.
    public func callContract(params: CallContractRequest) async -> String {
        let response = try! await signedClient.callContract(params)
        return response.txHash
    }
}
