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
        onRequestCompleted: { _ in },
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
