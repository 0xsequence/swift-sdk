import Foundation
import Testing
@testable import OMSWallet

private func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func credentialResponse(expiresAt: String) -> WaasAPI.GetCredential.Response {
    WaasAPI.GetCredential.Response(
        credential: WaasCredentialInfo(
            credentialId: "0xmock-credential",
            type: .direct,
            expiresAt: expiresAt,
            isCaller: true
        )
    )
}

@MainActor
private func waitUntil(attempts: Int = 40, _ condition: () -> Bool) async throws {
    for _ in 0..<attempts where !condition() {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

@Test @MainActor func TestRestoredSessionRefreshPersistsAndReschedulesExpiry() async throws {
    // The stored expiry is real-time future so restore accepts it; the server reports an earlier
    // sliding expiry, which must replace it in memory and storage and drive the timer.
    let base = Date()
    let storedExpiresAt = isoTimestamp(base.addingTimeInterval(30))
    let refreshedExpiresAt = isoTimestamp(base.addingTimeInterval(0.4))
    let now = LockedBox(base)
    let wallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-restored")
    let keychain = InMemoryKeychain()
    let environment = testEnvironment
    let projectId = "proj_\(UUID().uuidString)"
    let signer = MockCredentialSigner()
    let fixture = makeMockWalletClient(
        environment: environment,
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now.withValue { $0 } },
        storedCredentials: StorableCredentials(
            wallet: wallet,
            signerCredentialId: try signer.credentialId(),
            alg: signer.alg,
            expiresAt: storedExpiresAt,
            auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
        ),
        prepareTransport: { transport in
            try transport.enqueue(
                credentialResponse(expiresAt: refreshedExpiresAt),
                for: WaasAPI.GetCredential.urlPath
            )
            // The rescheduled timer refreshes again at the new expiry; an old server ends it.
            transport.enqueueWebRPCBadRoute(for: WaasAPI.GetCredential.urlPath)
        }
    )
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    try await waitUntil { fixture.client.session?.expiresAt == refreshedExpiresAt }
    #expect(fixture.client.session?.expiresAt == refreshedExpiresAt)
    #expect(try fixture.storedCredentials()?.expiresAt == refreshedExpiresAt)
    #expect(expiredEvents.isEmpty)

    now.withValue { $0 = base.addingTimeInterval(1) }
    try await waitUntil { !expiredEvents.isEmpty }

    #expect(expiredEvents.count == 1)
    #expect(expiredEvents.first?.expiredAt == refreshedExpiresAt)
    #expect(fixture.client.session == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 2)
}

@Test @MainActor func TestExpiryTimerKeepsSessionWhenRefreshIsUnavailable() async throws {
    let now = LockedBox(Date(timeIntervalSince1970: 1_767_225_599.8))
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let wallet = testWallet(id: "wallet-offline", address: "0x2222222222222222222222222222222222222222")
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [wallet],
            credential: WaasCredentialInfo(
                credentialId: "0xcredential",
                type: .direct,
                expiresAt: "2026-01-01T00:00:00Z",
                isCaller: true
            )
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "The Internet connection appears to be offline."),
        for: WaasAPI.GetCredential.urlPath
    )
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    _ = try await fixture.client.completeEmailAuth(code: "123456")
    now.withValue { $0 = Date(timeIntervalSince1970: 1_767_225_601) }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(expiredEvents.isEmpty)
    #expect(fixture.client.session?.expiresAt == "2026-01-01T00:00:00Z")
    #expect(fixture.client.activeWallet?.address == wallet.address)
}

@Test func TestLocallyExpiredOperationRefreshesExpiryAndContinues() async throws {
    let fixture = makeMockWalletClient(currentDate: { Date(timeIntervalSince1970: 1_767_225_601) })
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "2026-01-01T00:00:00Z"
    )
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2026-01-11T00:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsigned"), for: WaasAPI.SignMessage.urlPath)

    let signature = try await fixture.client.signMessage(network: .polygon, message: "hello")

    #expect(signature == "0xsigned")
    #expect(fixture.client.session?.expiresAt == "2026-01-11T00:00:00Z")
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

@Test func TestLocallyExpiredOperationThrowsNetworkErrorAndKeepsSessionWhenRefreshIsUnavailable() async throws {
    let fixture = makeMockWalletClient(currentDate: { Date(timeIntervalSince1970: 1_767_225_601) })
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "2026-01-01T00:00:00Z"
    )
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "The Internet connection appears to be offline."),
        for: WaasAPI.GetCredential.urlPath
    )

    do {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
        Issue.record("Expected the refresh's network error")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
        #expect(error.operation == .walletSignMessage)
    }

    #expect(fixture.client.session?.expiresAt == "2026-01-01T00:00:00Z")
    #expect(fixture.signer.clearCallCount == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 0)
}

@Test @MainActor func TestCredentialRefreshIsSharedAndIgnoredForReplacedSession() async throws {
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-first")
    )
    let gate = fixture.transport.holdResponses(for: WaasAPI.GetCredential.urlPath)
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2030-01-01T00:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )

    let client = fixture.client
    let first = Task { await client.refreshCredentialExpiry() }
    let second = Task { await client.refreshCredentialExpiry() }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }

    try fixture.client.signOut()
    let replacement = activeTestWallet("0x2222222222222222222222222222222222222222", id: "wallet-second")
    activateTestSession(fixture, wallet: replacement)
    gate.open()
    let outcomes = [await first.value, await second.value]

    for outcome in outcomes {
        guard case .superseded = outcome else {
            Issue.record("Expected a superseded refresh, got \(outcome)")
            continue
        }
    }
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.activeWallet?.id == replacement.id)
    #expect(fixture.client.session?.expiresAt == "2099-01-01T00:00:00Z")
    #expect(try fixture.storedCredentials() == nil)
}

@Test @MainActor func TestSignedRequestWaitsForInFlightCredentialRefresh() async throws {
    // WaaS needs strictly increasing nonces per credential, so an app request must not be signed
    // while the SDK's own refresh request is in flight.
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    )
    let gate = fixture.transport.holdResponses(for: WaasAPI.GetCredential.urlPath)
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2030-01-01T00:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsigned"), for: WaasAPI.SignMessage.urlPath)
    let client = fixture.client

    let refresh = Task { await client.refreshCredentialExpiry() }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    let sign = Task { try await client.signMessage(network: .polygon, message: "hello") }
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 0)

    gate.open()
    _ = await refresh.value
    let signature = try await sign.value

    #expect(signature == "0xsigned")
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 1)
    #expect(fixture.client.session?.expiresAt == "2030-01-01T00:00:00Z")
}
