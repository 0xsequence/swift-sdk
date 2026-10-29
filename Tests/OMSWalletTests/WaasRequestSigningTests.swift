import Foundation
import Testing
@testable import OMSWallet

@Test func TestSignedWaasClientCommitVerifierRequestSignsGeneratedPayload() async throws {
    try await expectSignedWaasRequest(
        nonce: "1710000003",
        response: CommitVerifierResponse(
            verifier: "verifier-123",
            loginHint: "user@example.com",
            challenge: "challenge"
        ),
        execute: { client in
            _ = try await client.commitVerifier(
                CommitVerifierRequest(
                    identityType: .email,
                    authMode: .otp,
                    metadata: [:],
                    handle: "user@example.com"
                )
            )
        },
        expectedPath: WaasAPI.CommitVerifier.urlPath,
        expectedPayload: [
            "identityType": "email",
            "authMode": "otp",
            "metadata": [:],
            "handle": "user@example.com"
        ]
    )
}

@Test func TestSignedWaasClientSignMessageRequestSignsGeneratedPayload() async throws {
    try await expectSignedWaasRequest(
        nonce: "1710000000",
        response: SignMessageResponse(signature: "0xsignature"),
        execute: { client in
            _ = try await client.signMessage(
                SignMessageRequest(
                    network: "80002",
                    walletId: "0x1234567890123456789012345678901234567890",
                    message: "hello"
                )
            )
        },
        expectedPath: WaasAPI.SignMessage.urlPath,
        expectedPayload: [
            "network": "80002",
            "walletId": "0x1234567890123456789012345678901234567890",
            "message": "hello"
        ]
    )
}

@Test func TestSignedWaasClientPrepareEthereumTransactionRequestSignsGeneratedPayload() async throws {
    try await expectSignedWaasRequest(
        nonce: "1710000001",
        response: PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: [],
            sponsored: false,
            expiresAt: "2099-01-01T00:00:00Z"
        ),
        execute: { client in
            _ = try await client.prepareEthereumTransaction(
                PrepareEthereumTransactionRequest(
                    network: "80002",
                    walletId: "0x1234567890123456789012345678901234567890",
                    to: "0xE5E8B483FfC05967FcFed58cc98D053265af6D99",
                    value: "1000",
                    mode: .relayer
                )
            )
        },
        expectedPath: WaasAPI.PrepareEthereumTransaction.urlPath,
        expectedPayload: [
            "network": "80002",
            "walletId": "0x1234567890123456789012345678901234567890",
            "to": "0xE5E8B483FfC05967FcFed58cc98D053265af6D99",
            "value": "1000",
            "mode": "relayer"
        ]
    )
}

@Test func TestSignedWaasClientCompleteAuthRequestSignsGeneratedPayload() async throws {
    let answer = RequestUtils.hashEmailAuthAnswer(
        challenge: "challenge",
        code: "123456"
    )
    try await expectSignedWaasRequest(
        nonce: "1710000002",
        response: CompleteAuthResponse(
            identity: Identity(type: .email, sub: "user@example.com"),
            wallets: [],
            email: "user@example.com",
            credential: WaasCredentialInfo(
                credentialId: testCredentialId,
                type: .direct,
                expiresAt: "2099-01-01T00:00:00Z",
                isCaller: true
            )
        ),
        execute: { client in
            _ = try await client.completeAuth(
                CompleteAuthRequest(
                    identityType: .email,
                    authMode: .otp,
                    verifier: "verifier-123",
                    answer: answer
                )
            )
        },
        expectedPath: WaasAPI.CompleteAuth.urlPath,
        expectedPayload: [
            "identityType": "email",
            "authMode": "otp",
            "verifier": "verifier-123",
            "answer": answer
        ]
    )
}

private let testPublishableKey = "pk_live_project_key"
private let testCredentialId = "0x04" + String(repeating: "11", count: 64)
private let testSignature = "0x" + String(repeating: "22", count: 64)

private func expectSignedWaasRequest<T: Encodable>(
    nonce: String,
    response: T,
    execute: (WaasClient) async throws -> Void,
    expectedPath: String,
    expectedPayload: [String: Any]
) async throws {
    let parsedKey = try parsePublishableKey(testPublishableKey)
    let recorder = WaasRequestRecorder(responseBody: try WebRPCJSON.makeEncoder().encode(response))
    let signer = RecordingCredentialSigner(nonce: nonce)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WaasRecordingURLProtocol.self]
    let host = WaasRecordingURLProtocol.register(recorder: recorder)
    let session = URLSession(configuration: configuration)
    let transport = SignedWaasTransport(
        publishableKey: testPublishableKey,
        scope: parsedKey.projectId,
        signer: signer,
        session: session
    )
    let client = WaasClient(
        baseURL: "https://\(host)",
        transport: transport
    )

    try await execute(client)

    let request = try #require(recorder.recordedRequest())
    let requestBody = try #require(recorder.recordedBody())
    let payload = try #require(String(data: requestBody, encoding: .utf8))
    let expectedPreimage = """
    POST \(expectedPath)
    nonce: \(nonce)
    scope: \(parsedKey.projectId)

    \(payload)
    """

    #expect(request.url?.path == expectedPath)
    #expect(try canonicalJSON(data: requestBody) == canonicalJSON(object: expectedPayload))
    #expect(signer.recordedPreimages() == [expectedPreimage])
    #expect(request.value(forHTTPHeaderField: "Api-Key") == testPublishableKey)
    #expect(request.value(forHTTPHeaderField: "Webrpc") == WEBRPC_HEADER_VALUE)
    #expect(
        request.value(forHTTPHeaderField: "OMS-Wallet-Signature")
            == expectedWalletSignatureHeader(nonce: nonce, scope: parsedKey.projectId)
    )
}

private func canonicalJSON(data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    return try canonicalJSON(object: object)
}

private func canonicalJSON(object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? ""
}

private func expectedWalletSignatureHeader(nonce: String, scope: String) -> String {
    "alg=\"ecdsa-p256-sha256\", scope=\"\(scope)\", cred=\"\(testCredentialId)\", nonce=\(nonce), sig=\"\(testSignature)\""
}

private final class WaasRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    let responseBody: Data
    private var body: Data?
    private var request: URLRequest?

    init(responseBody: Data) {
        self.responseBody = responseBody
    }

    func record(request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
        self.body = body
    }

    func recordedBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    func recordedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class WaasRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordersByHost: [String: WaasRequestRecorder] = [:]

    static func register(recorder: WaasRequestRecorder) -> String {
        let host = "waas-\(UUID().uuidString).test"
        lock.lock()
        defer { lock.unlock() }
        recordersByHost[host] = recorder
        return host
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let recorder = Self.recorder(for: request)
        recorder?.record(request: request, body: requestBodyData(request))

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: recorder?.responseBody ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func recorder(for request: URLRequest) -> WaasRequestRecorder? {
        guard let host = request.url?.host else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return recordersByHost[host]
    }

}

@available(macOS 12.0, iOS 15.0, *)
private final class RecordingCredentialSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256

    private let lock = NSLock()
    private let nonce: String
    private var preimages: [String] = []

    init(nonce: String) {
        self.nonce = nonce
    }

    func credentialId() throws -> String {
        testCredentialId
    }

    func nextNonce() throws -> String {
        nonce
    }

    func sign(preimage: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        preimages.append(preimage)
        return testSignature
    }

    func hasCredential() throws -> Bool {
        true
    }

    func clear() throws {}

    func recordedPreimages() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return preimages
    }
}

private let staleNonceBody = Data(
    #"{"error":"PreconditionFailed","code":7206,"msg":"Precondition failed; try again with a higher nonce value","status":412}"#.utf8
)

@Test func TestSessionCredentialTransportResignsStaleNonceRejection() async throws {
    let responses = StaleNonceResponses([
        (412, staleNonceBody),
        (200, try WebRPCJSON.makeEncoder().encode(SignMessageResponse(signature: "0xsigned")))
    ])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StaleNonceURLProtocol.self]
    let host = StaleNonceURLProtocol.register(responses)
    let signer = IncrementingNonceCredentialSigner()
    let client = WaasClient(
        baseURL: "https://\(host)",
        transport: SessionCredentialTransport(
            base: SignedWaasTransport(
                publishableKey: testPublishableKey,
                scope: "project",
                signer: signer,
                session: URLSession(configuration: configuration)
            ),
            gate: SignedRequestGate(),
            activeSessionRevision: { nil },
            onResponse: { _, _, _ in }
        )
    )

    let response = try await client.signMessage(
        SignMessageRequest(network: "polygon", walletId: "wallet-main", message: "hello")
    )

    let nonces = responses.recordedSignatureHeaders().map { header in
        header.components(separatedBy: ", ").first { $0.hasPrefix("nonce=") }.map { String($0.dropFirst(6)) }
    }
    #expect(response.signature == "0xsigned")
    #expect(nonces == ["1", "2"])
    #expect(signer.recordedPreimages().count == 2)
}

@Test func TestStaleNonceExecuteIsResentAndCompletes() async throws {
    // WaaS rejects a stale nonce in its credential middleware, before the Execute handler runs.
    let fixture = makeMockWalletClient()
    activateTestSession(fixture, wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"))
    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-stale-nonce",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2099-01-01T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    fixture.transport.enqueueRawHTTPError(statusCode: 412, body: staleNonceBody, for: WaasAPI.Execute.urlPath)
    try fixture.transport.enqueue(ExecuteResponse(status: .executed), for: WaasAPI.Execute.urlPath)

    let response = try await fixture.client.sendTransaction(
        network: .polygon,
        to: "0x2222222222222222222222222222222222222222",
        value: "0",
        waitForStatus: false
    )

    #expect(response.txnId == "txn-stale-nonce")
    #expect(fixture.transport.requestCount(for: WaasAPI.Execute.urlPath) == 2)
    #expect(fixture.client.activeWallet?.id == "wallet-main")
}

private final class StaleNonceResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    private var signatureHeaders: [String] = []

    init(_ responses: [(Int, Data)]) {
        self.responses = responses
    }

    func next(signatureHeader: String?) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        signatureHeaders.append(signatureHeader ?? "")
        return responses.isEmpty ? (500, Data()) : responses.removeFirst()
    }

    func recordedSignatureHeaders() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return signatureHeaders
    }
}

private final class StaleNonceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responsesByHost: [String: StaleNonceResponses] = [:]

    static func register(_ responses: StaleNonceResponses) -> String {
        let host = "waas-stale-nonce-\(UUID().uuidString).test"
        lock.lock()
        defer { lock.unlock() }
        responsesByHost[host] = responses
        return host
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let responses = request.url?.host.flatMap { Self.responsesByHost[$0] }
        Self.lock.unlock()
        let (statusCode, body) = responses?.next(
            signatureHeader: request.value(forHTTPHeaderField: "OMS-Wallet-Signature")
        ) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@available(macOS 12.0, iOS 15.0, *)
private final class IncrementingNonceCredentialSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256

    private let lock = NSLock()
    private var nonce = 0
    private var preimages: [String] = []

    func credentialId() throws -> String {
        testCredentialId
    }

    func nextNonce() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        nonce += 1
        return String(nonce)
    }

    func sign(preimage: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        preimages.append(preimage)
        return testSignature
    }

    func hasCredential() throws -> Bool {
        true
    }

    func clear() throws {}

    func recordedPreimages() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return preimages
    }
}
