import Foundation

@available(macOS 12.0, *)
@available(iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport {
    public let session: URLSession
    
    private let projectAccessKey: String;
    private var signer: [UInt8] = []
    
    public init(projectAccessKey: String, privateKey: [UInt8], session: URLSession = .shared) {
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
        
        print(endpoint)
        
        return await try! sendPost(baseURL: baseURL, path: path, payload: payload, headers: [
            "X-Access-Key": projectAccessKey,
            "Authorization": authHeader
        ])
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
    
    private func sendPost(
        baseURL: String,
        path: String,
        payload: String,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        guard let url = URL(string: joinWebRPCURL(baseURL: baseURL, path: path)) else {
            throw WebRPCTransportError(message: "Invalid WebRPC URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://localhost:3000", forHTTPHeaderField: "Origin")
        
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let responseHeaders = (httpResponse?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String else {
                    return
                }
                result[key] = String(describing: item.value)
            }

            return WebRPCHTTPResponse(
                statusCode: httpResponse?.statusCode ?? 0,
                body: data,
                headers: responseHeaders,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WebRPCTransportError(
                message: "WebRPC HTTP request failed",
                underlyingDescription: String(describing: error),
            )
        }
    }
    
    private func joinWebRPCURL(baseURL: String, path: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
