import Foundation

@available(macOS 12.0, iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport {
    public let session: URLSession

    private let client: HttpClient = HttpClient()
    private let publishableKey: String
    private let scope: String
    private let signer: any CredentialSigner

    public init(publishableKey: String,
                scope: String,
                signer: any CredentialSigner,
                session: URLSession = .shared
    ) {
        self.publishableKey = publishableKey
        self.scope = scope
        self.signer = signer
        self.session = session
    }

    public func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let endpoint = resolveEndpoint(path)
        let payload = String(data: body, encoding: .utf8) ?? ""

        let authHeader = try buildAuthHeader(
            endpoint: endpoint,
            scope: self.scope,
            signer: signer,
            payload: payload
        )

        var requestHeaders = [
            "X-Access-Key": publishableKey,
            "Oms-Wallet-Signature": authHeader
        ]
        for (name, value) in headers {
            requestHeaders[name] = value
        }

        let response = try await self.client.postJson(
            baseUrl: baseURL,
            path: path,
            body: payload,
            headers: requestHeaders
        )

        return WebRPCHTTPResponse(
            statusCode: response.statusCode,
            body: response.body
        )
    }

    private func buildAuthHeader(endpoint: String, scope: String, signer: any CredentialSigner, payload: String) throws -> String {
        let nonce = try signer.nextNonce()
        let preimage = RequestUtils.buildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, scope: scope, payload: payload)
        let signature = try signer.sign(preimage: preimage)

        return try RequestUtils.buildWalletSignatureHeader(
            alg: signer.alg,
            scope: scope,
            cred: signer.credentialId(),
            nonce: nonce,
            sig: signature
        )
    }

    private func resolveEndpoint(_ path: String) -> String {
        if path.hasPrefix(WaasWalletAPI.basePath) {
            return String(path.dropFirst(WaasWalletAPI.basePath.count))
        }
        if path.hasPrefix("/") {
            return path
        }
        return "/\(path)"
    }
}
