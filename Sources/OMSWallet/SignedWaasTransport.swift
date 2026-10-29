import Foundation

@available(macOS 12.0, iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport, ReportsSendStart {
    public let session: URLSession

    private let client: HttpClient
    private let publishableKey: PublishableKeyHolder
    private let scope: String
    private let signer: any CredentialSigner

    public init(publishableKey: String,
                scope: String,
                signer: any CredentialSigner,
                session: URLSession = .shared
    ) {
        self.init(publishableKey: PublishableKeyHolder(publishableKey), scope: scope, signer: signer, session: session)
    }

    init(publishableKey: PublishableKeyHolder,
         scope: String,
         signer: any CredentialSigner,
         session: URLSession = .shared
    ) {
        self.publishableKey = publishableKey
        self.scope = scope
        self.signer = signer
        self.session = session
        self.client = HttpClient(session: session)
    }

    public func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let endpoint = resolveEndpoint(path)
        let payload = String(data: body, encoding: .utf8) ?? ""
        let publishableKey = self.publishableKey.current

        let authHeader: String
        let scope = self.scope
        let signer = self.signer
        do {
            authHeader = try await SignerWork.run {
                try Self.buildAuthHeader(endpoint: endpoint, scope: scope, signer: signer, payload: payload)
            }
        } catch {
            throw RequestNotSentError(underlying: error)
        }
        // A request whose caller gave up (or whose deadline passed) while it was signed is not sent.
        try Task.checkCancellation()
        guard SignedRequestAttempt.current?.markSending() ?? true else {
            throw RequestNotSentError(underlying: CancellationError())
        }

        var requestHeaders = [
            "Api-Key": publishableKey,
            "OMS-Wallet-Signature": authHeader
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

    private static func buildAuthHeader(endpoint: String, scope: String, signer: any CredentialSigner, payload: String) throws -> String {
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
        if path.hasPrefix(WaasAPI.basePath) {
            return String(path.dropFirst(WaasAPI.basePath.count))
        }
        if path.hasPrefix("/") {
            return path
        }
        return "/\(path)"
    }
}

/// Runs synchronous signer work (keychain reads, nonce updates, signing) on a dedicated queue. A
/// signer can block its thread, and on the cooperative pool that could hold up the task that
/// enforces the request's deadline (a single cooperative thread on a small machine).
enum SignerWork {
    private static let queue = DispatchQueue(
        label: "technology.polygon.omswallet.signer",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }
}
