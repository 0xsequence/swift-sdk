class IntentSender {
    @available(macOS 12.0, *)
    @available(iOS 15.0, *)
    public func SignAndSend<T: Codable>(endpoint: String, signer: [UInt8], params: T) async -> String {
        let payload = try! params.toJSONString(pretty: true)
        
        let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: signer)
        
        let nonce = TimeUtils.currentTimestampInSecondsString()
        
        let preimage = RequestUtils.BuildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let signature = try! EthereumSigner.signUTF8MessageEIP191(privateKey: signer, message: hashedResult)
        
        let authHeader = RequestUtils.BuildAuthorizationHeader(scope: "@1:test", cred: walletAddress, nonce: nonce, sig: signature)
        
        let client = HttpClient(baseURL: "https://d1sctl7y41hot5.cloudfront.net/rpc/Wallet");
        let response = try! await client.SendPostRequest(endpoint: endpoint, payload: payload, authorizationHeader: authHeader, accessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE")
        return response
    }
}
