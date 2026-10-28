import Foundation
import Testing
@testable import OMSWallet

private struct SigningFailure: Error {}

/// A signer whose keychain operations fail, as when its key cannot be read.
private final class FailingCredentialSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256

    func credentialId() throws -> String { "0xfailing-credential" }
    func nextNonce() throws -> String { throw SigningFailure() }
    func sign(preimage: String) throws -> String { throw SigningFailure() }
    func hasCredential() throws -> Bool { true }
    func clear() throws {}
}

/// A transport whose requests never complete until their task is cancelled.
private final class HangingTransport: WebRPCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var cancellations = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func post(baseURL: String, path: String, body: Data, headers: [String: String]) async throws -> WebRPCHTTPResponse {
        recordCall()
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            recordCancellation()
            throw error
        }
        return WebRPCHTTPResponse(statusCode: 200, body: Data("{}".utf8))
    }

    private func recordCall() {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
    }

    private func recordCancellation() {
        lock.lock()
        defer { lock.unlock() }
        cancellations += 1
    }
}

private func sessionTransport(
    base: any WebRPCTransport,
    gate: SignedRequestGate = SignedRequestGate(),
    deadlineSeconds: TimeInterval
) -> SessionCredentialTransport {
    SessionCredentialTransport(
        base: base,
        gate: gate,
        activeSessionRevision: { nil },
        onRequestCompleted: { _, _ in },
        onResponse: { _, _, _ in },
        deadlineSeconds: deadlineSeconds
    )
}

@Test func TestSigningFailureIsReportedAsNotSent() async throws {
    let transport = SignedWaasTransport(publishableKey: "pk", scope: "project", signer: FailingCredentialSigner())

    do {
        _ = try await transport.post(baseURL: "https://waas.invalid", path: "/rpc/Waas/Execute", body: Data("{}".utf8), headers: [:])
        Issue.record("Expected signing to fail")
    } catch let error as RequestNotSentError {
        #expect(error.underlying is SigningFailure)
    }
}

@Test func TestExecuteThatFailedBeforeSendingIsRequestFailure() async throws {
    // Nothing reached WaaS, so the transaction is not unconfirmed and has no `txnId` to check.
    let fixture = makeMockWalletClient()
    activateTestSession(fixture, wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"))
    try fixture.transport.enqueue(
        PrepareResponse(txnId: "txn-unsent", status: .quoted, feeOptions: [], sponsored: true, expiresAt: "2099-01-01T00:00:00Z"),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    fixture.transport.enqueueError(RequestNotSentError(underlying: SigningFailure()), for: WaasAPI.Execute.urlPath)

    do {
        _ = try await fixture.client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x2222222222222222222222222222222222222222", value: "0")
        )
        Issue.record("Expected the unsent Execute to fail")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
        #expect(error.txnId == nil)
    }
}

@Test func TestRequestThatNeverGetsItsTurnIsNotSentAfterTheDeadline() async throws {
    let gate = SignedRequestGate()
    // An expiry read holds the gate and never finishes.
    try await gate.acquire()
    let base = MockWaasTransport()
    let transport = sessionTransport(base: base, gate: gate, deadlineSeconds: 0.2)
    let record = RequestSendRecord()

    do {
        _ = try await RequestSendRecord.$current.withValue(record) {
            try await transport.post(baseURL: "https://waas.test", path: WaasAPI.Execute.urlPath, body: Data("{}".utf8), headers: [:])
        }
        Issue.record("Expected the deadline to pass")
    } catch is RequestNotSentError {}

    #expect(record.failedBeforeSending)
    #expect(base.totalRequestCount == 0)
    // The expired waiter left the gate as it was: once the read ends, requests run again.
    gate.release()
    try await gate.acquire()
    gate.release()
}

@Test func TestRequestThatHangsAfterItWasSentTimesOutAsPossiblySent() async throws {
    let gate = SignedRequestGate()
    let base = HangingTransport()
    let transport = sessionTransport(base: base, gate: gate, deadlineSeconds: 0.2)
    let record = RequestSendRecord()

    do {
        _ = try await RequestSendRecord.$current.withValue(record) {
            try await transport.post(baseURL: "https://waas.test", path: WaasAPI.Execute.urlPath, body: Data("{}".utf8), headers: [:])
        }
        Issue.record("Expected the deadline to pass")
    } catch is RequestNotSentError {
        Issue.record("A request that was sent must not be reported as not sent")
    } catch let error as URLError {
        #expect(error.code == .timedOut)
    }

    #expect(!record.failedBeforeSending)
    #expect(base.callCount == 1)
    // The caller is answered before the request is cancelled; wait for the cancellation to land.
    for _ in 0..<100 where base.cancellationCount == 0 {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(base.cancellationCount == 1)
    // The request released the gate when it was cancelled.
    try await gate.acquire()
    gate.release()
}

@Test func TestCancelledWaiterDoesNotHoldTheGate() async throws {
    let gate = SignedRequestGate()
    try await gate.acquire()
    let read = Task { try await gate.acquire() }
    // Let the read start waiting behind the request.
    try await Task.sleep(nanoseconds: 50_000_000)
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }

    let acquired = LockedBox(false)
    let request = Task {
        try await gate.acquire()
        acquired.withValue { $0 = true }
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(!acquired.withValue { $0 })
    // The release goes to the waiting request, not to the cancelled read.
    gate.release()
    for _ in 0..<40 where !acquired.withValue({ $0 }) {
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    #expect(acquired.withValue { $0 })
    gate.release()
    _ = try await request.value
}

// MARK: - A signer that blocks past the deadline

/// Counts the HTTP requests sent to its host, per path, and answers them from `responses`.
private final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: [String: Int]] = [:]
    nonisolated(unsafe) private static var responses: [String: [String: Data]] = [:]

    static func register(responses: [String: Data] = [:]) -> String {
        let host = "count-\(UUID().uuidString.lowercased()).test"
        lock.lock()
        counts[host] = [:]
        self.responses[host] = responses
        lock.unlock()
        return host
    }

    static func count(host: String, pathSuffix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return (counts[host] ?? [:]).filter { $0.key.hasSuffix(pathSuffix) }.map(\.value).reduce(0, +)
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return counts[host] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.counts[host, default: [:]][path, default: 0] += 1
        let body = Self.responses[host]?.first { path.hasSuffix($0.key) }?.value ?? Data("{}".utf8)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Blocks its thread for `blockSeconds` while signing a preimage that contains `blockOn`, as a
/// keychain operation waiting on the system can.
private final class BlockingSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256
    private let blockOn: String
    private let blockSeconds: TimeInterval
    private let lock = NSLock()
    private var nonce = 0
    private var signing = false

    init(blockOn: String, blockSeconds: TimeInterval) {
        self.blockOn = blockOn
        self.blockSeconds = blockSeconds
    }

    var isSigning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return signing
    }

    func credentialId() throws -> String { "0xmock-credential" }
    func hasCredential() throws -> Bool { true }
    func clear() throws {}

    func nextNonce() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        nonce += 1
        return String(nonce)
    }

    func sign(preimage: String) throws -> String {
        if preimage.contains(blockOn) {
            setSigning(true)
            Thread.sleep(forTimeInterval: blockSeconds)
            setSigning(false)
        }
        return "0xsignature"
    }

    private func setSigning(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        signing = value
    }
}

@Test func TestBlockingSignerReturnsAtTheDeadlineWithoutSending() async throws {
    let host = CountingURLProtocol.register()
    let signer = BlockingSigner(blockOn: "SignMessage", blockSeconds: 1.5)
    let gate = SignedRequestGate()
    let transport = sessionTransport(
        base: SignedWaasTransport(publishableKey: "pk", scope: "prj_project", signer: signer, session: CountingURLProtocol.session()),
        gate: gate,
        deadlineSeconds: 0.2
    )
    let record = RequestSendRecord()

    let started = Date()
    do {
        _ = try await RequestSendRecord.$current.withValue(record) {
            try await transport.post(baseURL: "https://\(host)", path: WaasAPI.SignMessage.urlPath, body: Data("{}".utf8), headers: [:])
        }
        Issue.record("Expected the deadline to pass")
    } catch is RequestNotSentError {}

    // The caller has its answer at the deadline, while the signer is still running.
    #expect(Date().timeIntervalSince(started) < 1)
    #expect(signer.isSigning)
    #expect(record.failedBeforeSending)
    // The request keeps its turn until its signer stops; then it ends without sending.
    try await gate.acquire()
    #expect(!signer.isSigning)
    gate.release()
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(CountingURLProtocol.count(host: host, pathSuffix: "/SignMessage") == 0)
}

@Test func TestExecuteSignedPastTheDeadlineIsARequestFailure() async throws {
    // Nothing reached WaaS, so the transaction is not unconfirmed and has no `txnId` to check.
    let host = CountingURLProtocol.register(responses: [
        "/PrepareEthereumTransaction": try WebRPCJSON.makeEncoder().encode(
            PrepareResponse(txnId: "txn-unsent", status: .quoted, feeOptions: [], sponsored: true, expiresAt: "2099-01-01T00:00:00Z")
        )
    ])
    let signer = BlockingSigner(blockOn: "/Execute", blockSeconds: 1)
    let projectId = "prj_\(UUID().uuidString)"
    let client = WalletClient(
        publishableKey: "pk",
        projectId: projectId,
        environment: testEnvironment,
        credentialSession: WalletCredentialSession(
            environment: testEnvironment,
            projectId: projectId,
            keychain: InMemoryKeychain(),
            signerFactory: { _, _, _ in signer }
        ),
        signedClient: WaasClient(baseURL: "https://\(host)", transport: MockWaasTransport()),
        publicClient: WaasPublicClient(baseURL: "https://\(host)", transport: MockWaasTransport())
    )
    client.signedRequestDeadlineSeconds = 0.3
    client.signedClient = WaasClient(
        baseURL: "https://\(host)",
        transport: SignedWaasTransport(publishableKey: "pk", scope: projectId, signer: signer, session: CountingURLProtocol.session())
    )
    client.activeWallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    client.sessionAuth = .email(OMSWalletEmailSessionAuth(email: "user@example.com"))

    do {
        _ = try await client.sendTransaction(
            network: .polygon,
            request: SendTransactionRequest(to: "0x2222222222222222222222222222222222222222", value: "0")
        )
        Issue.record("Expected the Execute to time out")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
        #expect(error.txnId == nil)
    }

    try await Task.sleep(nanoseconds: 1_200_000_000)
    #expect(CountingURLProtocol.count(host: host, pathSuffix: "/PrepareEthereumTransaction") == 1)
    #expect(CountingURLProtocol.count(host: host, pathSuffix: "/Execute") == 0)
}

@Test func TestCancelledCallerIsAnsweredAtOnceWhileItsSignerRuns() async throws {
    let host = CountingURLProtocol.register()
    let signer = BlockingSigner(blockOn: "SignMessage", blockSeconds: 2)
    let gate = SignedRequestGate()
    let transport = sessionTransport(
        base: SignedWaasTransport(publishableKey: "pk", scope: "prj_project", signer: signer, session: CountingURLProtocol.session()),
        gate: gate,
        deadlineSeconds: 5
    )
    let caller = Task {
        try await transport.post(baseURL: "https://\(host)", path: WaasAPI.SignMessage.urlPath, body: Data("{}".utf8), headers: [:])
    }
    for _ in 0..<100 where !signer.isSigning {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    let cancelledAt = Date()
    caller.cancel()
    await #expect(throws: CancellationError.self) { try await caller.value }

    #expect(Date().timeIntervalSince(cancelledAt) < 1)
    #expect(signer.isSigning)
    // The request keeps its turn until its signer stops, and then sends nothing.
    try await gate.acquire()
    #expect(!signer.isSigning)
    gate.release()
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(CountingURLProtocol.count(host: host, pathSuffix: "/SignMessage") == 0)
}

// MARK: - Session activity

/// Records each request completion the transport reports.
private final class CompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var completions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func record(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
    }
}

private func recordingTransport(
    base: any WebRPCTransport,
    recorder: CompletionRecorder,
    deadlineSeconds: TimeInterval = SessionCredentialTransport.requestDeadlineSeconds
) -> SessionCredentialTransport {
    SessionCredentialTransport(
        base: base,
        gate: SignedRequestGate(),
        activeSessionRevision: { 1 },
        onRequestCompleted: { path, _ in recorder.record(path) },
        onResponse: { _, _, _ in },
        deadlineSeconds: deadlineSeconds,
        sessionRevision: { 1 }
    )
}

@Test func TestRequestThatWasNeverSentIsNotSessionActivity() async throws {
    // Only a request that may have reached WaaS can have extended the session.
    let host = CountingURLProtocol.register()
    let failedSigning = CompletionRecorder()
    _ = try? await recordingTransport(
        base: SignedWaasTransport(publishableKey: "pk", scope: "prj_project", signer: FailingCredentialSigner()),
        recorder: failedSigning
    ).post(baseURL: "https://\(host)", path: WaasAPI.SignMessage.urlPath, body: Data("{}".utf8), headers: [:])

    let signer = BlockingSigner(blockOn: "SignMessage", blockSeconds: 0.5)
    let expiredWhileSigning = CompletionRecorder()
    _ = try? await recordingTransport(
        base: SignedWaasTransport(publishableKey: "pk", scope: "prj_project", signer: signer, session: CountingURLProtocol.session()),
        recorder: expiredWhileSigning,
        deadlineSeconds: 0.1
    ).post(baseURL: "https://\(host)", path: WaasAPI.SignMessage.urlPath, body: Data("{}".utf8), headers: [:])
    // Let the signer finish; its request then ends without being sent.
    try await Task.sleep(nanoseconds: 700_000_000)

    let sent = CompletionRecorder()
    _ = try await recordingTransport(
        base: SignedWaasTransport(publishableKey: "pk", scope: "prj_project", signer: BlockingSigner(blockOn: "-", blockSeconds: 0), session: CountingURLProtocol.session()),
        recorder: sent
    ).post(baseURL: "https://\(host)", path: WaasAPI.SignMessage.urlPath, body: Data("{}".utf8), headers: [:])

    #expect(failedSigning.completions.isEmpty)
    #expect(expiredWhileSigning.completions.isEmpty)
    #expect(sent.completions == [WaasAPI.SignMessage.urlPath])
}
