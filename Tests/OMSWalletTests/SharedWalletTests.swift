import Foundation
import Testing
@testable import OMSWallet

/// A publishable key for a project no other test uses, so the process-wide registry starts empty
/// for it.
private func uniqueProjectKey(prefix: String = "pk_dev_sdbx_", keyId: String = "key1") -> (key: String, project: String) {
    let project = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return ("\(prefix)\(project)_\(keyId)", project)
}

// MARK: - One wallet per project and environment

@Test func TestCreatingOMSWalletAgainReturnsTheSameWallet() throws {
    let (key, _) = uniqueProjectKey()

    let first = try OMSWallet(publishableKey: key)
    let second = try OMSWallet(publishableKey: key)

    #expect(first.wallet === second.wallet)
    #expect(first.indexer === first.wallet.indexerClient)
    #expect(second.indexer === first.wallet.indexerClient)
}

@Test func TestConcurrentConstructionMakesOneWallet() throws {
    let (key, _) = uniqueProjectKey()
    let wallets = LockedBox<[ObjectIdentifier]>([])

    DispatchQueue.concurrentPerform(iterations: 64) { _ in
        guard let omsWallet = try? OMSWallet(publishableKey: key) else {
            return
        }
        wallets.withValue { $0.append(ObjectIdentifier(omsWallet.wallet)) }
    }

    #expect(wallets.withValue { $0.count } == 64)
    #expect(wallets.withValue { Set($0).count } == 1)
}

@Test func TestAnotherProjectOrEnvironmentGetsItsOwnWallet() throws {
    let (key, project) = uniqueProjectKey()
    let (otherProjectKey, _) = uniqueProjectKey()
    let otherEnvironmentKey = "pk_stg_sdbx_\(project)_key1"

    let wallet = try OMSWallet(publishableKey: key).wallet

    #expect(try OMSWallet(publishableKey: otherProjectKey).wallet !== wallet)
    #expect(try OMSWallet(publishableKey: otherEnvironmentKey).wallet !== wallet)
}

// MARK: - A rotated publishable key

@Test func TestRotatedKeyKeepsTheSessionAndIsUsedForLaterRequests() throws {
    let registry = WalletClientRegistry()
    let fixture = makeMockWalletClient()
    activateTestSession(fixture, wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"))
    let scope = "test-scope"
    _ = registry.client(scope: scope, publishableKey: "pk_dev_sdbx_project_key1") { fixture.client }

    let shared = registry.client(scope: scope, publishableKey: "pk_dev_sdbx_project_key2") {
        Issue.record("The scope already has a client")
        return fixture.client
    }

    #expect(shared === fixture.client)
    #expect(shared.activeWallet?.id == "wallet-main")
    #expect(shared.publishableKeyHolder.current == "pk_dev_sdbx_project_key2")
}

@Test func TestRotatedKeyReachesEveryTransport() async throws {
    let (key1, project) = uniqueProjectKey()
    let key2 = "pk_dev_sdbx_\(project)_key2"
    let omsWallet = try OMSWallet(publishableKey: key1)
    _ = try OMSWallet(publishableKey: key2)

    #expect(omsWallet.wallet.publicClient.headers()["Api-Key"] == key2)
    #expect(omsWallet.wallet.publishableKeyHolder.current == key2)
}

@Test func TestSignedRequestSendsTheKeyCurrentWhenItStarts() async throws {
    let holder = PublishableKeyHolder("pk_old")
    // Rotating the key while a request is being signed leaves that request's key as it was.
    let signer = RotatingSigner { holder.update("pk_new") }
    let host = ApiKeyRecordingURLProtocol.register()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ApiKeyRecordingURLProtocol.self]
    let transport = SignedWaasTransport(
        publishableKey: holder,
        scope: "prj_project",
        signer: signer,
        session: URLSession(configuration: configuration)
    )

    _ = try await transport.post(baseURL: "https://\(host)", path: "/rpc/Waas/SignMessage", body: Data("{}".utf8), headers: [:])
    _ = try await transport.post(baseURL: "https://\(host)", path: "/rpc/Waas/SignMessage", body: Data("{}".utf8), headers: [:])

    #expect(ApiKeyRecordingURLProtocol.recordedKeys(host: host) == ["pk_old", "pk_new"])
}

/// A signer that runs `onFirstSign` while it signs its first request.
private final class RotatingSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256
    private let onFirstSign: () -> Void
    private let lock = NSLock()
    private var signed = false

    init(onFirstSign: @escaping () -> Void) {
        self.onFirstSign = onFirstSign
    }

    func credentialId() throws -> String { "0xrotating" }
    func nextNonce() throws -> String { "1" }
    func hasCredential() throws -> Bool { true }
    func clear() throws {}

    func sign(preimage: String) throws -> String {
        lock.lock()
        let isFirst = !signed
        signed = true
        lock.unlock()
        if isFirst {
            onFirstSign()
        }
        return "0xsignature"
    }
}

/// Records the `Api-Key` header of each request to its host, and answers `{}`.
private final class ApiKeyRecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [String: [String]] = [:]

    static func register() -> String {
        let host = "keys-\(UUID().uuidString.lowercased()).test"
        lock.lock()
        keys[host] = []
        lock.unlock()
        return host
    }

    static func recordedKeys(host: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return keys[host] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return keys[host] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let host = request.url?.host {
            Self.lock.lock()
            Self.keys[host, default: []].append(request.value(forHTTPHeaderField: "Api-Key") ?? "")
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - A key replaced by another process

/// A wallet session signed in through `createSequenceWallet`, which records its signer credential.
private func signedInFixture(
    expiresAt: String = "2099-01-01T00:00:00Z",
    currentDate: @escaping () -> Date = Date.init
) throws -> MockWalletClientFixture {
    let fixture = makeMockWalletClient(currentDate: currentDate)
    try fixture.client.createSequenceWallet(
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        sessionMetadata: SessionMetadata(
            expiresAt: expiresAt,
            auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com")),
            expiryBounds: testExpiryBounds
        ),
        requiredSessionRevision: fixture.client.sessionRevisionSnapshot()
    )
    return fixture
}

@Test func TestOperationAfterAnotherProcessSignedInAgainFailsWithoutSending() async throws {
    let fixture = try signedInFixture()
    // Another process sharing the keychain signs in again: a new key and a new stored session.
    fixture.signer.replaceKey(credentialId: "0xnewer-credential")
    let newerRecord = StorableCredentials(
        wallet: activeTestWallet("0x2222222222222222222222222222222222222222", id: "wallet-newer"),
        signerCredentialId: "0xnewer-credential",
        alg: fixture.signer.alg,
        expiresAt: "2099-01-01T00:00:00Z",
        auth: .email(OMSWalletEmailSessionAuth(email: "other@example.com")),
        expiryBounds: testExpiryBounds
    )
    try fixture.keychain.set(
        try newerRecord.jsonString(),
        forKey: Constants.credentialsStorageKey(environment: fixture.environment, scope: fixture.projectId)
    )

    await #expect {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
    } throws: { error in
        (error as? OMSWalletError)?.code == .sessionMissing
    }

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(fixture.transport.totalRequestCount == 0)
    // The key and stored session now belong to the newer session and are left alone.
    #expect(fixture.signer.clearCallCount == 0)
    #expect(try fixture.storedCredentials()?.wallet.id == "wallet-newer")
    #expect(try fixture.storedCredentials()?.signerCredentialId == "0xnewer-credential")
}

@Test func TestOperationAfterAnotherProcessSignedOutFailsAndEndsTheSession() async throws {
    let fixture = try signedInFixture()
    // Another process sharing the keychain signs out: its stored session and key are deleted.
    try fixture.client.credentialSession.clear()

    await #expect {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
    } throws: { error in
        (error as? OMSWalletError)?.code == .sessionMissing
    }

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.transport.totalRequestCount == 0)
}

@Test @MainActor func TestBackgroundReadThatFindsTheKeyReplacedReportsASignOut() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let fixture = try signedInFixture(currentDate: { now })
    let events = LockedBox<[OMSWalletSessionChangeEvent]>([])
    let observation = fixture.client.addSessionChangeObserver { event in events.withValue { $0.append(event) } }
    fixture.signer.replaceKey(credentialId: "0xnewer-credential")

    _ = await fixture.client.refreshCredentialExpiry()
    for _ in 0..<40 where events.withValue({ $0.isEmpty }) {
        try await Task.sleep(nanoseconds: 25_000_000)
    }

    // Another sign-in replaced the key before the session's expiry (2099) passed.
    #expect(events.withValue { $0 } == [.signedOut])
    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
    #expect(fixture.signer.clearCallCount == 0)
    observation.cancel()
}

@Test @MainActor func TestKeyReplacedAfterTheExpiryReportsTheExpiry() async throws {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)
    let fixture = try signedInFixture(
        expiresAt: ISO8601DateFormatter().string(from: expiry),
        currentDate: { expiry.addingTimeInterval(60) }
    )
    let events = LockedBox<[OMSWalletSessionChangeEvent]>([])
    let observation = fixture.client.addSessionChangeObserver { event in events.withValue { $0.append(event) } }
    fixture.signer.replaceKey(credentialId: "0xnewer-credential")

    _ = await fixture.client.refreshCredentialExpiry()
    for _ in 0..<40 where events.withValue({ $0.isEmpty }) {
        try await Task.sleep(nanoseconds: 25_000_000)
    }

    #expect(events.withValue { $0.last?.expiredSession?.expiredAt } == ISO8601DateFormatter().string(from: expiry))
    observation.cancel()
}

// MARK: - One signed request at a time

/// Applies WaaS's nonce rule: accepts a request only when its nonce exceeds the last one accepted,
/// and answers 7206 otherwise. Each request takes its nonce when it starts and reaches the server
/// after a delay that is longer for earlier nonces, so requests in flight together arrive out of
/// order.
private final class ConditionalWriteWaas: WebRPCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var nextNonce = 0
    private var lastAccepted = 0
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var accepted: [Int] = []
    private(set) var rejections = 0
    let requestCount: Int

    init(requestCount: Int) {
        self.requestCount = requestCount
    }

    func post(baseURL: String, path: String, body: Data, headers: [String: String]) async throws -> WebRPCHTTPResponse {
        let nonce = withLock { () -> Int in
            nextNonce += 1
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return nextNonce
        }
        try await Task.sleep(nanoseconds: UInt64(max(1, requestCount - nonce)) * 2_000_000)
        return withLock {
            inFlight -= 1
            guard nonce > lastAccepted else {
                rejections += 1
                return WebRPCHTTPResponse(
                    statusCode: 412,
                    body: Data(#"{"error":"PreconditionFailed","code":7206,"msg":"Precondition failed; try again with a higher nonce value","status":412}"#.utf8)
                )
            }
            lastAccepted = nonce
            accepted.append(nonce)
            return WebRPCHTTPResponse(statusCode: 200, body: Data("{}".utf8))
        }
    }

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@Test func TestConcurrentSignedRequestsGoOutOneAtATimeWithoutNonceRejections() async throws {
    let requestCount = 12
    let waas = ConditionalWriteWaas(requestCount: requestCount)
    let transport = SessionCredentialTransport(
        base: waas,
        gate: SignedRequestGate(),
        activeSessionRevision: { nil },
        onRequestCompleted: { _, _ in },
        onResponse: { _, _, _ in }
    )

    let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<requestCount {
            group.addTask {
                try await transport.post(
                    baseURL: "https://waas.test",
                    path: WaasAPI.SignMessage.urlPath,
                    body: Data("{}".utf8),
                    headers: [:]
                ).statusCode
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }

    #expect(statuses == Array(repeating: 200, count: requestCount))
    #expect(waas.withLock { waas.rejections } == 0)
    #expect(waas.withLock { waas.maxInFlight } == 1)
    #expect(waas.withLock { waas.accepted } == Array(1...requestCount))
}

/// Holds requests to `held` until released; answers others at once.
private final class HoldingTransport: WebRPCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var heldRequestArrived = false
    private var release: CheckedContinuation<Void, Never>?
    let held: String

    init(held: String) {
        self.held = held
    }

    var hasHeldRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heldRequestArrived
    }

    func post(baseURL: String, path: String, body: Data, headers: [String: String]) async throws -> WebRPCHTTPResponse {
        if path == held {
            await withCheckedContinuation { continuation in
                lock.lock()
                heldRequestArrived = true
                release = continuation
                lock.unlock()
            }
        }
        return WebRPCHTTPResponse(statusCode: 200, body: Data("{}".utf8))
    }

    func releaseHeldRequest() {
        lock.lock()
        let release = self.release
        self.release = nil
        lock.unlock()
        release?.resume()
    }
}

@Test func TestRequestOfAnotherCredentialDoesNotWaitBehindAHeldOne() async throws {
    // A new sign-in replaces the key; its requests must not wait for the previous credential's.
    let waas = HoldingTransport(held: WaasAPI.CompleteAuth.urlPath)
    let signingCredential = LockedBox("0xold-credential")
    let transport = SessionCredentialTransport(
        base: waas,
        gate: SignedRequestGate(),
        activeSessionRevision: { nil },
        onRequestCompleted: { _, _ in },
        onResponse: { _, _, _ in },
        deadlineSeconds: 2,
        signingCredentialId: { signingCredential.withValue { $0 } }
    )
    let held = Task {
        try await transport.post(baseURL: "https://waas.test", path: WaasAPI.CompleteAuth.urlPath, body: Data("{}".utf8), headers: [:])
    }
    for _ in 0..<40 where !waas.hasHeldRequest {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(waas.hasHeldRequest)

    signingCredential.withValue { $0 = "0xnew-credential" }
    let started = Date()
    let response = try await transport.post(
        baseURL: "https://waas.test",
        path: WaasAPI.SignMessage.urlPath,
        body: Data("{}".utf8),
        headers: [:]
    )

    #expect(response.statusCode == 200)
    #expect(Date().timeIntervalSince(started) < 1)
    waas.releaseHeldRequest()
    _ = try await held.value
}

@Test func TestRequestOfAnEndedSessionIsNotTheNextSessionsActivity() async throws {
    let now = LockedBox(Date(timeIntervalSince1970: 1_800_000_000))
    let fixture = try signedInFixture(currentDate: { now.withValue { $0 } })
    let waas = HoldingTransport(held: WaasAPI.SignMessage.urlPath)
    fixture.client.signedClient = WaasClient(baseURL: fixture.environment.walletApiUrl, transport: waas)
    let client = fixture.client
    let request = Task {
        try await client.signMessage(network: .polygon, message: "hello")
    }
    for _ in 0..<100 where !waas.hasHeldRequest {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(waas.hasHeldRequest)

    // The session ends and another starts while the first one's request is still in flight.
    try fixture.client.clearSession(clearOidcRedirectAuth: false)
    try fixture.client.createSequenceWallet(
        wallet: activeTestWallet("0x2222222222222222222222222222222222222222", id: "wallet-next"),
        sessionMetadata: SessionMetadata(
            expiresAt: "2099-01-01T00:00:00Z",
            auth: .email(OMSWalletEmailSessionAuth(email: "next@example.com")),
            expiryBounds: testExpiryBounds
        ),
        requiredSessionRevision: fixture.client.sessionRevisionSnapshot()
    )
    let activityBefore = fixture.client.withSessionLock { fixture.client._lastSessionRequestCompletedAt }
    now.withValue { $0 = $0.addingTimeInterval(60) }
    waas.releaseHeldRequest()
    _ = try? await request.value

    #expect(fixture.client.withSessionLock { fixture.client._lastSessionRequestCompletedAt } == activityBefore)
}
