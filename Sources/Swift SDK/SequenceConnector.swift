public class SequenceConnector {
    @MainActor public static let shared = SequenceConnector()
    
    let intentSender: IntentSender = IntentSender()
    let keychain: KeychainManager = KeychainManager()
    
    let addressStorageKey: String = "sequence-wallet-address"
    let signerStorageKey: String = "sequence-local-signer"
    
    var privateKey: [UInt8] = []
    
    var verifier = "";
    var challenge = "";
    
    public init() {}
    
    public func RestoreSession() -> SequenceWallet {
        let walletAddress = try! keychain.string(forKey: addressStorageKey) ?? ""
        
        let signerPrivateKeyHex = try! keychain.string(forKey: signerStorageKey) ?? ""
        let signerPrivateKey = ByteUtils.HexToBytes(hex: signerPrivateKeyHex)
        
        return SequenceWallet(walletAddress: walletAddress, sessionPrivateKey: signerPrivateKey)
    }
    
    @available(macOS 12.0, *)
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
    
    @available(macOS 12.0, *)
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
    
    @available(macOS 12.0, *)
    public func CreateWallet() async -> SequenceWallet {
        return await CreateWalletByType(walletType: "Ethereum_SequenceV3");
    }
    
    @available(macOS 12.0, *)
    public func CreateWalletByType(walletType: String) async -> SequenceWallet {
        let params = CreateWalletParams(
            walletType: walletType
        )
        
        let response = await intentSender.SignAndSend(
            endpoint: "/CreateWallet",
            signer: self.privateKey,
            params: params
        )
        
        let walletData = try! WalletReturn.from(jsonString: response)
        
        return CreateSequenceWallet(address: walletData.address);
    }
    
    @available(macOS 12.0, *)
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
        
        let walletData = try! WalletReturn.from(jsonString: response)

        return CreateSequenceWallet(address: walletData.address);
    }
    
    private func CreateSequenceWallet(address: String) -> SequenceWallet {
        try! keychain.set(ByteUtils.BytesToHex(data: self.privateKey), forKey: signerStorageKey)
        return SequenceWallet(walletAddress: address, sessionPrivateKey: self.privateKey)
    }
}
