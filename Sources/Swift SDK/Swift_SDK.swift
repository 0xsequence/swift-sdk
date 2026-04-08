public class SwiftSDK {
    
    @MainActor public static let shared = SwiftSDK()
    
    var privateKey: [UInt8]? = nil
    
    var verifier = "";
    var challenge = "";
    
    public init() {}
    
    public func RestoreSession() {
        
    }
    
    @available(macOS 12.0, *)
    public func SignInWithEmail(email: String) async {
        privateKey = try! EthereumSigner.GeneratePrivateKey()
        
        let params = CommitVerifierParams(
            handle: email,
            authMode: "OTP",
            identityType: "Email",
        )

        let response = await SignAndSend(endpoint: "/CommitVerifier", params: params)
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
        
        let response = await SignAndSend(endpoint: "/CompleteAuth", params: params)
        let data = try! CompleteAuthReturn.from(jsonString: response)
        
        return data
    }
    
    @available(macOS 12.0, *)
    public func CreateWallet() async {
        let params = CreateWalletParams(
            walletType: "Ethereum_SequenceV3"
        )
        
        let response = await SignAndSend(endpoint: "/CreateWallet", params: params)
    }
    
    @available(macOS 12.0, *)
    public func CreateWalletByType(walletType: String) async {
        let params = CreateWalletParams(
            walletType: walletType
        )
        
        let response = await SignAndSend(endpoint: "/CreateWallet", params: params)
    }
    
    @available(macOS 12.0, *)
    public func UseWallet(walletType: String) async {
        let params = UseWalletParams(
            walletIndex: 0,
            walletType: walletType
        )
        
        let response = await SignAndSend(endpoint: "/UseWallet", params: params)
    }
    
    @available(macOS 12.0, *)
    private func SignAndSend<T: Codable>(endpoint: String, params: T) async -> String {
        let key = privateKey ?? []
        
        let envelope = ParamsEnvelope(params: params)
        let payload = try! envelope.toJSONString(pretty: true)
        
        let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: key)
        
        let nonce = TimeUtils.currentTimestampInSecondsString()
        
        let preimage = RequestUtils.BuildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let signature = try! EthereumSigner.signUTF8MessageEIP191(privateKey: key, message: hashedResult)
        
        let authHeader = RequestUtils.BuildAuthorizationHeader(scope: "@1:test", cred: walletAddress, nonce: nonce, sig: signature)
        
        let client = HttpClient(baseURL: "https://d1sctl7y41hot5.cloudfront.net/rpc/Wallet");
        let response = try! await client.SendPostRequest(endpoint: endpoint, payload: payload, authorizationHeader: authHeader, accessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE")
        return response
    }
}
