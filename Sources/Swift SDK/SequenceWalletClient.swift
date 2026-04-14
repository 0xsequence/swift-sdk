@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceWalletClient {
    var signedClient: WaasWalletClient
    let keychain: KeychainManager = KeychainManager()
    
    /// The on-chain address of this wallet.
    public let walletAddress: String
    
    var sessionPrivateKey: [UInt8]
    
    var verifier = "";
    var challenge = "";
    
    internal init(projectAccessKey: String) {
        if let walletAddress = try? keychain.string(forKey: Constants.addressStorageKey),
           let signerPrivateKeyHex = try? keychain.string(forKey: Constants.signerStorageKey) {
            self.walletAddress = walletAddress
            self.sessionPrivateKey = ByteUtils.hexToBytes(hex: signerPrivateKeyHex)
        } else {
            self.walletAddress = ""
            self.sessionPrivateKey = try! EthereumSigner.GeneratePrivateKey()
        }

        self.signedClient = WaasWalletClient(
            baseURL: Constants.apiUrl,
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
    /// `ConfirmEmailSignIn(code:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func signInWithEmail(email: String) async {
        let params = CommitVerifierRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            metadata: [String : String] (),
            handle: email
        )
        
        let response = await try! signedClient.commitVerifier(params)

        verifier = response.verifier ?? "undefined"
        challenge = response.challenge ?? "undefined"
    }
    
    /// Completes the email OTP authentication flow by verifying the code the user received.
    ///
    /// Must be called after `SignInWithEmail(email:)`. The challenge and verifier from the
    /// previous step are used automatically. On success, proceed to `CreateWallet()` or
    /// `UseWallet(walletType:)` to obtain a `SequenceWallet`.
    ///
    /// - Parameter code: The one-time passcode string entered by the user.
    /// - Returns: A `CompleteAuthReturn` value containing the result of the authentication attempt.
    public func confirmEmailSignIn(code: String) async -> CompleteAuthResponse {
        let answer = Keccak256.Keccak256(data: "\(challenge)\(code)")
        
        let params = CompleteAuthRequest(
            identityType: IdentityType.email,
            authMode: AuthMode.otp,
            verifier: verifier,
            answer: answer,
        )
        
        let response = await try! signedClient.completeAuth(params)
        
        return response
    }
    
    /// Creates a new Ethereum wallet (Sequence V3) for the authenticated user.
    ///
    /// The wallet address and session key are persisted to the keychain
    /// so `RestoreSession()` can rehydrate the session on future launches.
    ///
    /// - Returns: A `SequenceWallet` instance representing the newly created wallet.
    public func createWallet() async {
        return await createWalletByType(walletType: WalletType.ethereumSequenceV3);
    }
    
    /// Creates a new wallet of the specified type for the authenticated user.
    ///
    /// Use this instead of `CreateWallet()` when you need a wallet type other than
    /// the default `"Ethereum_SequenceV3"`. The wallet address and session key are
    /// persisted to the keychain automatically.
    ///
    /// - Parameter walletType: A string identifying the wallet type to create (e.g. `"Ethereum_SequenceV3"`).
    /// - Returns: A `SequenceWallet` instance representing the newly created wallet.
    public func createWalletByType(walletType: WalletType) async {
        let params = CreateWalletRequest(
            walletType: walletType
        )
        
        let response = await try! signedClient.createWallet(params)
        
        return createSequenceWallet(address: response.wallet.address ?? "");
    }
    
    /// Fetches an existing wallet of the specified type for the authenticated user.
    ///
    /// Use this when the user already has a wallet from a previous session and you want
    /// to load it by type rather than restoring from the keychain. The wallet address and
    /// session key are persisted to the keychain automatically.
    ///
    /// - Parameter walletType: A string identifying the wallet type to fetch (e.g. `"Ethereum_SequenceV3"`).
    /// - Returns: A `SequenceWallet` instance for the fetched wallet.
    public func useWallet(walletType: WalletType) async {
        let params = UseWalletRequest(
            walletType: walletType,
            walletIndex: 0
        )
        
        let response = await try! signedClient.useWallet(params)
        createSequenceWallet(address: response.wallet.address ?? "");
    }
    
    /// Persists the wallet address and session private key to the keychain, then returns
    /// a configured `SequenceWallet` instance.
    private func createSequenceWallet(address: String) {
        try! keychain.set(address, forKey: Constants.addressStorageKey)
        try! keychain.set(ByteUtils.bytesToHex(data: self.sessionPrivateKey), forKey: Constants.signerStorageKey)
    }
    
    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, `SequenceConnector.RestoreSession()` will return `nil` and
    /// the user will need to sign in again. Navigate to your sign-in screen after calling this.
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
            walletAddress: self.walletAddress
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
            walletAddress: self.walletAddress
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
            wallet: self.walletAddress,
            message: message
        )
        
        let response = await try! signedClient.signMessage(params)
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
            wallet: self.walletAddress,
            to: to,
            value: value,
            mode: TransactionMode.relayer
        )
        
        let response = await try! signedClient.sendTransaction(params)
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
        let response = await try! signedClient.callContract(params)
        return response.txHash
    }
}
