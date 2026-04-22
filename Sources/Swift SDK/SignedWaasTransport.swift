import Foundation

@available(macOS 12.0, iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport {
    public let session: URLSession
    
    private let client: HttpClient = HttpClient()
    private let projectAccessKey: String
    private var signer: [UInt8] = []
    
    public init(projectAccessKey: String,
                privateKey: [UInt8],
                session: URLSession = .shared
    ) {
        self.projectAccessKey = projectAccessKey
        self.signer = privateKey
        self.session = session
    }
    
    public func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let endpoint = "/\(path.split(separator: "/")[2])"
        let payload = String(data: body, encoding: .utf8) ?? ""
        let authHeader = buildAuthHeader(endpoint: endpoint, signer: signer, payload: payload)
        
        let response = try! await self.client.postJson(baseUrl: baseURL, path: path, body: payload, headers: [
            "X-Access-Key": projectAccessKey,
            "Authorization": authHeader
        ])
        
        return WebRPCHTTPResponse(
            statusCode: response.statusCode,
            body: response.body
        )
    }
    
    public mutating func setSigner(signer: [UInt8]) {
        self.signer = signer
    }
    
    private func buildAuthHeader(endpoint: String, signer: [UInt8], payload: String) -> String {
        let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: signer)
        
        let nonce = TimeUtils.currentTimestampInSecondsString()
        
        let preimage = RequestUtils.buildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let signature = try! EthereumSigner.signUTF8MessageEIP191(privateKey: signer, message: hashedResult)
        
        return RequestUtils.buildAuthorizationHeader(scope: Constants.scope, cred: walletAddress, nonce: nonce, sig: signature)
    }
}
