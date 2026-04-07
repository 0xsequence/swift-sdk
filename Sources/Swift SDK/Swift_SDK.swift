public class SwiftSDK {
    
    public init() {}
    
    public func Initialize(accessKey: String) {
        
    }
    
    public func RestoreSession() {
        
    }
    
    @available(macOS 12.0, *)
    public func SignInWithEmail(email: String) async {
        let params = CommitVerifierParams(
            handle: email,
            authMode: "OTP",
            identityType: "Email",
        )

        let response = await SignAndSend(endpoint: "/CommitVerifier", params: params)
        let data = try! SequenceCommitVerifierResponse.from(jsonString: response)
    }
    
    public func ConfirmEmailSignIn(email: String, code: String) {
        
    }
    
    public func CreateWallet() {
        
    }
    
    public func UseWallet(walletType: String) {
        
    }
    
    @available(macOS 12.0, *)
    private func SignAndSend<T: Codable>(endpoint: String, params: T) async -> String {
        let privateKey: [UInt8] = try! EthereumSigner.GeneratePrivateKey()
        
        let envelope = ParamsEnvelope(params: params)
        let payload = try! envelope.toJSONString(pretty: true)
        
        let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: privateKey)
        
        let nonce = TimeUtils.currentTimestampInSecondsString()
        
        let preimage = RequestUtils.BuildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let signature = try! EthereumSigner.signUTF8MessageEIP191(privateKey: privateKey, message: hashedResult)
        
        let authHeader = RequestUtils.BuildAuthorizationHeader(scope: "@1:test", cred: walletAddress, nonce: nonce, sig: signature)
        
        let client = HttpClient(baseURL: "https://d1sctl7y41hot5.cloudfront.net/rpc/Wallet");
        let response = try! await client.SendPostRequest(endpoint: endpoint, payload: payload, authorizationHeader: authHeader, accessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE")
        return response
    }
}
