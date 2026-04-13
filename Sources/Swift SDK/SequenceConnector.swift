@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceConnector {
    /// The shared singleton instance of `SequenceConnector`. Must be accessed on the main thread.
    @MainActor public static let shared = SequenceConnector()
    
    let intentSender: IntentSender = IntentSender()
    let keychain: KeychainManager = KeychainManager()
    
    var privateKey: [UInt8] = []
    
    var verifier = "";
    var challenge = "";
    
    public init() {}
    
    /// Attempts to restore a previously authenticated wallet session from the device keychain.
    ///
    /// Call this on app launch to check whether the user already has an active session,
    /// avoiding the need to re-authenticate.
    ///
    /// - Returns: A `SequenceWallet` instance if a valid session exists in the keychain, or `nil` if no session is found.
    public func RestoreSession() -> SequenceWallet? {
        guard
            let walletAddress = try? keychain.string(forKey: Constants.addressStorageKey),
            let signerPrivateKeyHex = try? keychain.string(forKey: Constants.signerStorageKey)
        else {
            return nil
        }
        
        let signerPrivateKey = ByteUtils.HexToBytes(hex: signerPrivateKeyHex)
        return SequenceWallet(walletAddress: walletAddress, sessionPrivateKey: signerPrivateKey)
    }
    
    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method generates a new session key pair and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `ConfirmEmailSignIn(code:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func SignInWithEmail(email: String) async {
        privateKey = try! EthereumSigner.GeneratePrivateKey()
        
        let params = CommitVerifierParams(
            handle: email,
            authMode: "OTP",
            identityType: "Email",
        )

        let response = await intentSender.SignAndSend(
            endpoint: "/CommitVerifier",
            signer: self.privateKey,
            params: params
        )
        
        let data = try! SequenceCommitVerifierResponse.from(jsonString: response)
        verifier = data.verifier ?? "undefined"
        challenge = data.challenge ?? "undefined"
    }
    
    /// Completes the email OTP authentication flow by verifying the code the user received.
    ///
    /// Must be called after `SignInWithEmail(email:)`. The challenge and verifier from the
    /// previous step are used automatically. On success, proceed to `CreateWallet()` or
    /// `UseWallet(walletType:)` to obtain a `SequenceWallet`.
    ///
    /// - Parameter code: The one-time passcode string entered by the user.
    /// - Returns: A `CompleteAuthReturn` value containing the result of the authentication attempt.
    public func ConfirmEmailSignIn(code: String) async -> CompleteAuthReturn {
        let answer = Keccak256.Keccak256(data: "\(challenge)\(code)")
        
        let params = CompleteAuthParams(
            answer: answer,
            verifier: verifier,
            authMode: "OTP",
            identityType: "Email"
        )
        
        let response = await intentSender.SignAndSend(
            endpoint: "/CompleteAuth",
            signer: self.privateKey,
            params: params
        )
        
        let data = try! CompleteAuthReturn.from(jsonString: response)
        
        return data
    }
    
    /// Creates a new Ethereum wallet (Sequence V3) for the authenticated user.
    ///
    /// The wallet address and session key are persisted to the keychain
    /// so `RestoreSession()` can rehydrate the session on future launches.
    ///
    /// - Returns: A `SequenceWallet` instance representing the newly created wallet.
    public func CreateWallet() async -> SequenceWallet {
        return await CreateWalletByType(walletType: "Ethereum_SequenceV3");
    }
    
    /// Creates a new wallet of the specified type for the authenticated user.
    ///
    /// Use this instead of `CreateWallet()` when you need a wallet type other than
    /// the default `"Ethereum_SequenceV3"`. The wallet address and session key are
    /// persisted to the keychain automatically.
    ///
    /// - Parameter walletType: A string identifying the wallet type to create (e.g. `"Ethereum_SequenceV3"`).
    /// - Returns: A `SequenceWallet` instance representing the newly created wallet.
    public func CreateWalletByType(walletType: String) async -> SequenceWallet {
        let params = CreateWalletParams(
            walletType: walletType
        )
        
        let response = await intentSender.SignAndSend(
            endpoint: "/CreateWallet",
            signer: self.privateKey,
            params: params
        )
        
        let walletData = try! WaasWalletResponse.from(jsonString: response)
        
        return CreateSequenceWallet(address: walletData.wallet.address);
    }
    
    /// Fetches an existing wallet of the specified type for the authenticated user.
    ///
    /// Use this when the user already has a wallet from a previous session and you want
    /// to load it by type rather than restoring from the keychain. The wallet address and
    /// session key are persisted to the keychain automatically.
    ///
    /// - Parameter walletType: A string identifying the wallet type to fetch (e.g. `"Ethereum_SequenceV3"`).
    /// - Returns: A `SequenceWallet` instance for the fetched wallet.
    public func UseWallet(walletType: String) async -> SequenceWallet {
        let params = UseWalletParams(
            walletIndex: 0,
            walletType: walletType
        )
        
        let response = await intentSender.SignAndSend(
            endpoint: "/UseWallet",
            signer: self.privateKey,
            params: params
        )
        
        let walletData = try! WaasWalletResponse.from(jsonString: response)

        return CreateSequenceWallet(address: walletData.wallet.address);
    }
    
    /// Persists the wallet address and session private key to the keychain, then returns
    /// a configured `SequenceWallet` instance.
    private func CreateSequenceWallet(address: String) -> SequenceWallet {
        try! keychain.set(address, forKey: Constants.addressStorageKey)
        try! keychain.set(ByteUtils.BytesToHex(data: self.privateKey), forKey: Constants.signerStorageKey)
        
        return SequenceWallet(walletAddress: address, sessionPrivateKey: self.privateKey)
    }
}
