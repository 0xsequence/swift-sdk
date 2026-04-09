@available(macOS 12.0, *)
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
    
    public func RestoreSession() -> SequenceWallet? {
        guard
            let walletAddress = try? keychain.string(forKey: addressStorageKey),
            let signerPrivateKeyHex = try? keychain.string(forKey: signerStorageKey)
        else {
            return nil
        }
        
        let signerPrivateKey = ByteUtils.HexToBytes(hex: signerPrivateKeyHex)
        return SequenceWallet(walletAddress: walletAddress, sessionPrivateKey: signerPrivateKey)
    }
    
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
    
    public func CreateWallet() async -> SequenceWallet {
        return await CreateWalletByType(walletType: "Ethereum_SequenceV3");
    }
    
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
    
    private func CreateSequenceWallet(address: String) -> SequenceWallet {
        try! keychain.set(address, forKey: addressStorageKey)
        try! keychain.set(ByteUtils.BytesToHex(data: self.privateKey), forKey: signerStorageKey)
        
        return SequenceWallet(walletAddress: address, sessionPrivateKey: self.privateKey)
    }
}
