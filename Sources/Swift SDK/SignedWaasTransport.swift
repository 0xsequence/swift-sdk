import Foundation

@available(macOS 12.0, *)
@available(iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport {
    public let session: URLSession
    
    private var signer: [UInt8] = []
    
    public init(privateKey: [UInt8], session: URLSession = .shared) {
        self.signer = privateKey
        self.session = session
    }
    
    public func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let authHeader = buildAuthHeader(endpoint: path, signer: signer, payload: body.base64EncodedString());
        return WebRPCHTTPResponse(statusCode: 200, body: Data())
    }
    
    public mutating func setSigner(signer: [UInt8]) {
        self.signer = signer
    }
    
    private func buildAuthHeader(endpoint: String, signer: [UInt8], payload: String) -> String {
        let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: signer)
        
        let nonce = TimeUtils.currentTimestampInSecondsString()
        
        let preimage = RequestUtils.BuildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, payload: payload)
        
        let hashedResult = Keccak256.Keccak256(data: preimage)
        let signature = try! EthereumSigner.signUTF8MessageEIP191(privateKey: signer, message: hashedResult)
        
        return RequestUtils.BuildAuthorizationHeader(scope: "@1:test", cred: walletAddress, nonce: nonce, sig: signature)
    }
    
    private func sendPost(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        guard let url = URL(string: joinWebRPCURL(baseURL: baseURL, path: path)) else {
            throw WebRPCTransportError(message: "Invalid WebRPC URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

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
