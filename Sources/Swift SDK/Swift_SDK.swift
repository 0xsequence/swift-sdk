public class SwiftSDK {
    
    public init() {}
    
    public func Initialize(accessKey: String) {
        
    }
    
    public func RestoreSession() {
        
    }
    
    @available(macOS 12.0, *)
    public func SignInWithEmail(email: String) async {
        let params = CommitVerifierParams(
            identityType: "email",
            authMode: "oauth",
            handle: email
        )

        let respones = await SignAndSend(endpoint: "/CommitVerifier", params: params)
    }
    
    public func ConfirmEmailSignIn(email: String, code: String) {
        
    }
    
    public func CreateWallet() {
        
    }
    
    public func UseWallet(walletType: String) {
        
    }
    
    @available(macOS 12.0, *)
    private func SignAndSend<T: Codable>(endpoint: String, params: T) async -> String {
        let privateKey: [UInt8] = [
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
            0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11
        ]
        
        let envelope = ParamsEnvelope(params: params)
        let payload = try! envelope.toJSONString(pretty: true)
        
        let preimage = RequestUtils.BuildWalletRequestPreimage(endpoint: endpoint, nonce: "0", payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let result = try! EthereumSigner.signUTF8MessageEIP191(privateKey: privateKey, message: hashedResult)
        
        let authHeader = RequestUtils.BuildAuthorizationHeader(scope: "@1:test", cred: "0x00", nonce: "0", sig: preimage)
        
        let client = HttpClient(baseURL: "https://d1sctl7y41hot5.cloudfront.net/rpc/Wallet");
        let response = try! await client.SendPostRequest(endpoint: endpoint, payload: payload, authorizationHeader: authHeader, accessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE")
        return response
    }
}
