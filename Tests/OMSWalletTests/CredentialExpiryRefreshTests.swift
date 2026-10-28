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
            auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com")),
            expiryBounds: testExpiryBounds
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

    now.withValue { $0 = base.addingTimeInterval(1 + WalletClient.sessionExpiryCheckGraceSeconds) }
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
    now.withValue {
        $0 = Date(timeIntervalSince1970: 1_767_225_601 + WalletClient.sessionExpiryCheckGraceSeconds)
    }
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

@Test @MainActor func TestCredentialRefreshWaitsForInFlightSignedRequests() async throws {
    // The other direction of the nonce ordering: a refresh must not be signed while an app request
    // is in flight, and app requests that start while the refresh waits queue behind it.
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    )
    let client = fixture.client
    // A first refresh stamps the refresh time, so the app calls below start no background refresh.
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2030-01-01T00:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )
    _ = await client.refreshCredentialExpiry()

    let gate = fixture.transport.holdResponses(for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xfirst"), for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsecond"), for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2031-01-01T00:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )

    let first = Task { try await client.signMessage(network: .polygon, message: "first") }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 1 }
    let refresh = Task { await client.refreshCredentialExpiry() }
    try await Task.sleep(nanoseconds: 50_000_000)
    let second = Task { try await client.signMessage(network: .polygon, message: "second") }
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 1)

    gate.open()
    #expect(try await first.value == "0xfirst")
    _ = await refresh.value
    #expect(try await second.value == "0xsecond")

    #expect(fixture.transport.requestPaths == [
        WaasAPI.GetCredential.urlPath,
        WaasAPI.SignMessage.urlPath,
        WaasAPI.GetCredential.urlPath,
        WaasAPI.SignMessage.urlPath,
    ])
    #expect(fixture.client.session?.expiresAt == "2031-01-01T00:00:00Z")
}

@Test @MainActor func TestSuccessfulSignedCallRefreshesExpiryInBackgroundEverySixHours() async throws {
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let wallet = testWallet(id: "wallet-main", address: "0x2222222222222222222222222222222222222222")
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [wallet],
            credential: WaasCredentialInfo(
                credentialId: "0xcredential",
                type: .direct,
                expiresAt: "2026-01-11T00:00:00Z",
                isCaller: true
            )
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)
    for signature in ["0xone", "0xtwo", "0xthree"] {
        try fixture.transport.enqueue(SignMessageResponse(signature: signature), for: WaasAPI.SignMessage.urlPath)
    }
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: "2026-01-11T06:00:00Z"),
        for: WaasAPI.GetCredential.urlPath
    )

    // Sign-in counts as a refresh, so a call right after it starts none.
    _ = try await fixture.client.completeEmailAuth(code: "123456")
    _ = try await fixture.client.signMessage(network: .polygon, message: "one")
    now.withValue { $0 = base.addingTimeInterval(6 * 60 * 60 - 1) }
    _ = try await fixture.client.signMessage(network: .polygon, message: "two")
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    // Six hours after sign-in, a successful call refreshes the expiry in the background.
    now.withValue { $0 = base.addingTimeInterval(6 * 60 * 60) }
    _ = try await fixture.client.signMessage(network: .polygon, message: "three")
    try await waitUntil { fixture.client.session?.expiresAt == "2026-01-11T06:00:00Z" }
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.session?.expiresAt == "2026-01-11T06:00:00Z")
}

private let unauthorizedBody = Data(
    #"{"error":"Unauthorized","code":7207,"msg":"Unauthorized","cause":"credential revoked","status":401}"#.utf8
)
private let keyExpiredBody = Data(#"{"error":"KeyExpired","code":7203,"msg":"key expired","status":400}"#.utf8)

/// Signs in through `completeEmailAuth` with a credential that expires at `expiresAt`.
@MainActor
private func signIn(_ fixture: MockWalletClientFixture, expiresAt: Date) async throws {
    let wallet = testWallet(id: "wallet-main", address: "0x2222222222222222222222222222222222222222")
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [wallet],
            credential: WaasCredentialInfo(
                credentialId: "0xcredential",
                type: .direct,
                expiresAt: isoTimestamp(expiresAt),
                isCaller: true
            )
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)
    _ = try await fixture.client.completeEmailAuth(code: "123456")
}

private func sessionExpiryTimerFireDate(_ client: WalletClient) -> Date? {
    client.withSessionLock { client._sessionExpiryTimerFireDate }
}

private func isSameInstant(_ lhs: Date?, _ rhs: Date) -> Bool {
    guard let lhs else {
        return false
    }
    return abs(lhs.timeIntervalSince(rhs)) < 0.001
}

@Test @MainActor func TestExpiryTimerEndsSessionWhenCredentialRefreshIsUnauthorized() async throws {
    // GetCredential involves no wallet, so its 7207 means the credential was revoked.
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = base.addingTimeInterval(0.5)
    try await signIn(fixture, expiresAt: expiry)
    fixture.transport.enqueueRawHTTPError(statusCode: 401, body: unauthorizedBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    now.withValue { $0 = expiry.addingTimeInterval(WalletClient.sessionExpiryCheckGraceSeconds + 1) }
    try await waitUntil { !expiredEvents.isEmpty }
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(expiredEvents.count == 1)
    #expect(expiredEvents.first?.wallet?.id == "wallet-main")
    #expect(fixture.client.session == nil)
    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

@Test @MainActor func TestLocallyExpiredOperationThrowsSessionExpiredWhenCredentialRefreshIsUnauthorized() async throws {
    let fixture = makeMockWalletClient(currentDate: { Date(timeIntervalSince1970: 1_767_225_601) })
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "2026-01-01T00:00:00Z"
    )
    fixture.transport.enqueueRawHTTPError(statusCode: 401, body: unauthorizedBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    do {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
        Issue.record("Expected sessionExpired")
    } catch let error as OMSWalletError {
        #expect(error.code == .sessionExpired)
        #expect(error.operation == .walletSignMessage)
        #expect(error.upstreamError == nil)
    }
    try await waitUntil { !expiredEvents.isEmpty }

    #expect(expiredEvents.count == 1)
    #expect(fixture.client.session == nil)
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 0)
}

@Test func TestCredentialRefreshKeepsSessionForGatewayUnauthorized() async throws {
    // The API gateway also names an error "Unauthorized", with code 1000; only WaaS's 7207 counts.
    let fixture = makeMockWalletClient(currentDate: { Date(timeIntervalSince1970: 1_767_225_601) })
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "2026-01-01T00:00:00Z"
    )
    fixture.transport.enqueueRawHTTPError(
        statusCode: 401,
        body: Data(#"{"error":"Unauthorized","code":1000,"msg":"Unauthorized","status":401}"#.utf8),
        for: WaasAPI.GetCredential.urlPath
    )

    do {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
        Issue.record("Expected the refresh's request error")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
        #expect(error.upstreamError?.code == "1000")
    }

    #expect(fixture.client.session?.expiresAt == "2026-01-01T00:00:00Z")
    #expect(fixture.signer.clearCallCount == 0)
}

@Test @MainActor func TestExpiryTimerDefersCheckAfterActivitySinceLastRead() async throws {
    // A signed request after the last credential read slid the server's expiry past the local one,
    // so the timer waits for that later expiry instead of asking (and extending) now.
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = base.addingTimeInterval(0.5)
    try await signIn(fixture, expiresAt: expiry)
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsigned"), for: WaasAPI.SignMessage.urlPath)
    now.withValue { $0 = base.addingTimeInterval(0.2) }
    _ = try await fixture.client.signMessage(network: .polygon, message: "hello")

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    let checkDate = expiry.addingTimeInterval(0.2 + WalletClient.sessionExpiryCheckGraceSeconds)
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate) }
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
    #expect(fixture.client.activeWallet?.id == "wallet-main")
}

@Test @MainActor func TestExpiryTimerWithoutActivityChecksAfterGracePeriodAndEndsExpiredSession() async throws {
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = base.addingTimeInterval(0.5)
    try await signIn(fixture, expiresAt: expiry)
    fixture.transport.enqueueRawHTTPError(statusCode: 400, body: keyExpiredBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    // Before L + G the timer only reschedules itself to L + G.
    let checkDate = expiry.addingTimeInterval(WalletClient.sessionExpiryCheckGraceSeconds)
    now.withValue { $0 = checkDate.addingTimeInterval(-1) }
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate) }
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
    #expect(fixture.client.activeWallet?.id == "wallet-main")

    // The rescheduled timer would sleep in real time; fire it now that L + G has passed.
    now.withValue { $0 = checkDate.addingTimeInterval(1) }
    fixture.client.scheduleSessionExpiry(try #require(fixture.client.currentSessionSnapshot()))
    try await waitUntil { !expiredEvents.isEmpty }

    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(expiredEvents.count == 1)
    #expect(fixture.client.session == nil)
}

@Test @MainActor func TestExpiryTimerAppliesServerExtendedExpiryAndReschedules() async throws {
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = base.addingTimeInterval(0.5)
    let extendedExpiry = base.addingTimeInterval(3_600)
    try await signIn(fixture, expiresAt: expiry)
    try fixture.transport.enqueue(
        credentialResponse(expiresAt: isoTimestamp(extendedExpiry)),
        for: WaasAPI.GetCredential.urlPath
    )
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    now.withValue { $0 = expiry.addingTimeInterval(WalletClient.sessionExpiryCheckGraceSeconds + 1) }
    try await waitUntil { fixture.client.session?.expiresAt == isoTimestamp(extendedExpiry) }
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(fixture.client), extendedExpiry) }

    #expect(fixture.client.session?.expiresAt == isoTimestamp(extendedExpiry))
    #expect(try fixture.storedCredentials()?.expiresAt == isoTimestamp(extendedExpiry))
    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), extendedExpiry))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(expiredEvents.isEmpty)
    #expect(fixture.client.activeWallet?.id == "wallet-main")
}

@Test @MainActor func TestExpiryTimerCountsManualWalletSelectionAsActivity() async throws {
    // The selection's UseWallet request, sent after the sign-in read, slid the server's expiry.
    let base = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(base)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = base.addingTimeInterval(0.5)
    let wallet = testWallet(id: "wallet-main", address: "0x2222222222222222222222222222222222222222")
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [wallet],
            credential: WaasCredentialInfo(
                credentialId: "0xcredential",
                type: .direct,
                expiresAt: isoTimestamp(expiry),
                isCaller: true
            )
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)

    let result = try await fixture.client.completeEmailAuth(code: "123456", walletSelection: .manual)
    guard case .walletSelection(let selection) = result else {
        Issue.record("Expected a pending wallet selection")
        return
    }
    now.withValue { $0 = base.addingTimeInterval(0.2) }
    _ = try await selection.selectWallet(walletId: wallet.id)

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    let checkDate = expiry.addingTimeInterval(0.2 + WalletClient.sessionExpiryCheckGraceSeconds)
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate) }

    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), checkDate))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

// MARK: - Expiry timer bounds (idle window I and ceiling N from sign-in)

private let day: TimeInterval = 24 * 60 * 60
private let hour: TimeInterval = 60 * 60
private let grace = WalletClient.sessionExpiryCheckGraceSeconds

/// Signs in at the fixture's current time, requesting `lifetimeSeconds`, with a credential that
/// expires at `expiresAt`.
@MainActor
private func signIn(_ fixture: MockWalletClientFixture, lifetimeSeconds: UInt32, expiresAt: Date) async throws {
    fixture.client.pendingEmailAuth = PendingEmailAuth(
        email: "user@example.com",
        sessionLifetimeSeconds: lifetimeSeconds
    )
    try await signIn(fixture, expiresAt: expiresAt)
}

/// Fires the expiry timer at the current mock time; a scheduled timer sleeps in real time.
private func fireExpiryTimer(_ client: WalletClient) throws {
    client.scheduleSessionExpiry(try #require(client.currentSessionSnapshot()))
}

/// Fires the expiry timer and waits until it has rescheduled itself for `checkDate`.
@MainActor
private func expectTimerDefers(_ client: WalletClient, to checkDate: Date) async throws {
    try fireExpiryTimer(client)
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(client), checkDate) }
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(isSameInstant(sessionExpiryTimerFireDate(client), checkDate))
}

/// Fires the expiry timer once its check is due, with WaaS answering `GetCredential` with 7203, and
/// expects the session to end.
@MainActor
private func expectTimerEndsSession(_ fixture: MockWalletClientFixture, getCredentialCount: Int) async throws {
    fixture.transport.enqueueRawHTTPError(statusCode: 400, body: keyExpiredBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }
    try fireExpiryTimer(fixture.client)
    try await waitUntil { !expiredEvents.isEmpty }
    #expect(expiredEvents.count == 1)
    #expect(fixture.client.session == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == getCredentialCount)
}

@MainActor
private func signMessage(_ fixture: MockWalletClientFixture) async throws {
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsigned"), for: WaasAPI.SignMessage.urlPath)
    _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
}

@MainActor
private func waitForCredentialRefreshToFinish(_ client: WalletClient) async throws {
    try await waitUntil { client.withSessionLock { client._credentialRefresh == nil } }
}

@Test @MainActor func TestExpiryTimerWaitsForIdleWindowAfterActivityFollowingDampenedRead() async throws {
    // A read 1 hour after sign-in returns the sign-in expiry (WaaS skips moves under 6 hours), so
    // activity at 6h50m moves the server's expiry 6h50m past it, not just A - C = 5h50m.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)

    now.withValue { $0 = signInAt.addingTimeInterval(hour) }
    try fixture.transport.enqueue(credentialResponse(expiresAt: isoTimestamp(expiry)), for: WaasAPI.GetCredential.urlPath)
    _ = await fixture.client.refreshCredentialExpiry()
    let activityAt = signInAt.addingTimeInterval(6 * hour + 50 * 60)
    now.withValue { $0 = activityAt }
    try await signMessage(fixture)

    let checkDate = activityAt.addingTimeInterval(10 * day + grace)
    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: checkDate)
    // Past the old L + (A - C) + grace, the session may still be live on the server.
    now.withValue { $0 = expiry.addingTimeInterval(5 * hour + 50 * 60 + grace + 1) }
    try await expectTimerDefers(fixture.client, to: checkDate)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.activeWallet?.id == "wallet-main")

    now.withValue { $0 = checkDate.addingTimeInterval(1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 2)
}

@Test @MainActor func TestExpiryTimerChecksAtFixedExpiryForLifetimeShorterThanIdleWindow() async throws {
    // A 1-hour lifetime fixes the expiry at the ceiling, so activity cannot delay the check.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(hour)
    try await signIn(fixture, lifetimeSeconds: 3_600, expiresAt: expiry)
    now.withValue { $0 = signInAt.addingTimeInterval(30 * 60) }
    try await signMessage(fixture)

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: expiry.addingTimeInterval(grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    now.withValue { $0 = expiry.addingTimeInterval(grace + 1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 1)
}

@Test @MainActor func TestExpiryTimerCapsCheckAtCeilingNearEndOfLifetime() async throws {
    // A 12-day lifetime with a 10-day idle window: activity on day 9 cannot move the expiry past
    // day 12. The background read it starts fails, so the last successful read stays the sign-in.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    let ceiling = signInAt.addingTimeInterval(12 * day)
    try await signIn(fixture, lifetimeSeconds: UInt32(12 * day), expiresAt: expiry)
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "The request timed out."),
        for: WaasAPI.GetCredential.urlPath
    )
    now.withValue { $0 = signInAt.addingTimeInterval(9 * day) }
    try await signMessage(fixture)
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    try await waitForCredentialRefreshToFinish(fixture.client)

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: ceiling.addingTimeInterval(grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)

    now.withValue { $0 = ceiling.addingTimeInterval(grace + 1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 2)
}

@Test @MainActor func TestExpiryTimerChecksAfterGraceWithoutActivitySinceLastRead() async throws {
    // Activity at 3h, then a read at 4h returning the sign-in expiry: nothing was sent after the
    // read, so the server's expiry is the one it returned.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    now.withValue { $0 = signInAt.addingTimeInterval(3 * hour) }
    try await signMessage(fixture)
    now.withValue { $0 = signInAt.addingTimeInterval(4 * hour) }
    try fixture.transport.enqueue(credentialResponse(expiresAt: isoTimestamp(expiry)), for: WaasAPI.GetCredential.urlPath)
    _ = await fixture.client.refreshCredentialExpiry()

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: expiry.addingTimeInterval(grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)

    now.withValue { $0 = expiry.addingTimeInterval(grace + 1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 2)
}

@Test @MainActor func TestExpiryTimerCountsSentButFailedCredentialReadAsActivity() async throws {
    // A read whose response is lost may still have moved the server's expiry when it was sent. Here
    // it is the read a wallet call makes on a locally expired session, before the timer's check.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    let readAt = expiry.addingTimeInterval(60)
    now.withValue { $0 = readAt }
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "The request timed out."),
        for: WaasAPI.GetCredential.urlPath
    )
    do {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
        Issue.record("Expected the read's network error")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
    }
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 0)

    now.withValue { $0 = readAt.addingTimeInterval(60) }
    try await expectTimerDefers(fixture.client, to: readAt.addingTimeInterval(10 * day + grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.activeWallet?.id == "wallet-main")
}

@Test @MainActor func TestExpiryTimerCheckFailingOfflineRetriesWithBackoffAtSameCheckTime() async throws {
    // The timer's own read is sent after the bound on the server's expiry, so it is not activity:
    // after it fails, the retry follows the backoff instead of waiting another idle window.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    let lastActivity = fixture.client.withSessionLock { fixture.client._lastSessionRequestCompletedAt }
    fixture.transport.enqueueTransportError(
        WebRPCTransportError(message: "The Internet connection appears to be offline."),
        for: WaasAPI.GetCredential.urlPath
    )

    let checkedAt = expiry.addingTimeInterval(grace + 1)
    now.withValue { $0 = checkedAt }
    try fireExpiryTimer(fixture.client)
    let retryAt = checkedAt.addingTimeInterval(WalletClient.sessionExpiryRetryDelay(attempt: 1))
    try await waitUntil { isSameInstant(sessionExpiryTimerFireDate(fixture.client), retryAt) }
    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), retryAt))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.withSessionLock { fixture.client._lastSessionRequestCompletedAt } == lastActivity)
    #expect(fixture.client.activeWallet?.id == "wallet-main")

    // The retry, due after the backoff, asks again rather than deferring.
    now.withValue { $0 = retryAt.addingTimeInterval(1) }
    fixture.transport.enqueueRawHTTPError(statusCode: 400, body: keyExpiredBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }
    fixture.client.scheduleSessionExpiry(
        try #require(fixture.client.currentSessionSnapshot()),
        retryAttempt: 1,
        at: now.withValue { $0 }
    )
    try await waitUntil { !expiredEvents.isEmpty }
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 2)
    #expect(fixture.client.session == nil)
}

@Test @MainActor func TestExpiryBoundsPersistAcrossRestoreAndDriveExpiryTimer() async throws {
    // Restore checks the stored expiry against the real clock, so the times start now.
    let signInAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let now = LockedBox(signInAt)
    let keychain = InMemoryKeychain()
    let projectId = "proj_\(UUID().uuidString)"
    let signer = MockCredentialSigner()
    let first = makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now.withValue { $0 } }
    )
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(first, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    let expectedBounds = try #require(
        SessionExpiryBounds(
            idleWindowSeconds: 10 * day,
            ceilingEpochSeconds: signInAt.timeIntervalSince1970 + Double(WalletClient.maxSessionLifetimeSeconds)
        )
    )
    let stored = try #require(try first.storedCredentials())
    #expect(stored.idleWindowSeconds == 10 * day)
    #expect(stored.expiryCeilingEpochSeconds == expectedBounds.ceilingEpochSeconds)

    // A new client restores the session; its read 1 hour after sign-in returns the sign-in expiry.
    now.withValue { $0 = signInAt.addingTimeInterval(hour) }
    let restored = makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now.withValue { $0 } },
        prepareTransport: { transport in
            try transport.enqueue(credentialResponse(expiresAt: isoTimestamp(expiry)), for: WaasAPI.GetCredential.urlPath)
        }
    )
    #expect(restored.client.activeWallet?.id == "wallet-main")
    #expect(restored.client.withSessionLock { restored.client._sessionExpiryBounds } == expectedBounds)
    try await waitUntil { restored.client.withSessionLock { restored.client._lastCredentialRefreshAt != nil } }
    try await waitForCredentialRefreshToFinish(restored.client)
    // The refresh rewrote the stored record and kept the bounds.
    #expect(try restored.storedCredentials()?.expiryBounds == expectedBounds)

    let activityAt = signInAt.addingTimeInterval(6 * hour + 50 * 60)
    now.withValue { $0 = activityAt }
    try await signMessage(restored)
    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(restored.client, to: activityAt.addingTimeInterval(10 * day + grace))
    #expect(restored.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

/// Stores a session record for `expiresAt`, with `fields` merged into its JSON.
private func storeSessionRecord(
    keychain: InMemoryKeychain,
    projectId: String,
    signer: MockCredentialSigner,
    expiresAt: Date,
    fields: [String: Any]
) throws {
    let record = StorableCredentials(
        wallet: activeTestWallet("0x2222222222222222222222222222222222222222", id: "wallet-main"),
        signerCredentialId: try signer.credentialId(),
        alg: signer.alg,
        expiresAt: isoTimestamp(expiresAt),
        auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    )
    var object = try #require(
        try JSONSerialization.jsonObject(with: Data(record.jsonString().utf8)) as? [String: Any]
    )
    #expect(object["idleWindowSeconds"] == nil)
    #expect(object["expiryCeilingEpochSeconds"] == nil)
    object.merge(fields) { _, new in new }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    try keychain.set(json, forKey: Constants.credentialsStorageKey(environment: testEnvironment, scope: projectId))
}

@Test(arguments: [
    [:],
    ["idleWindowSeconds": -1.0, "expiryCeilingEpochSeconds": 4_102_444_800.0],
    ["idleWindowSeconds": "864000", "expiryCeilingEpochSeconds": 4_102_444_800.0],
    ["idleWindowSeconds": 864_000.0],
] as [[String: any Sendable]])
func TestStoredSessionWithoutValidExpiryBoundsIsDiscardedOnRestore(_ fields: [String: any Sendable]) throws {
    // Only pre-release 0.4.0 builds wrote records without the bounds; like any invalid record they
    // are discarded, and the user signs in again.
    let keychain = InMemoryKeychain()
    let projectId = "proj_\(UUID().uuidString)"
    let signer = MockCredentialSigner()
    let expiry = Date().addingTimeInterval(10 * day)
    try storeSessionRecord(keychain: keychain, projectId: projectId, signer: signer, expiresAt: expiry, fields: fields)

    let fixture = makeMockWalletClient(projectId: projectId, keychain: keychain, signer: signer)

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(try fixture.storedCredentials() == nil)
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

@Test @MainActor func TestExpiryTimerAfterFailedRestoreReadWaitsForBoundFromRestoreTime() async throws {
    // Nothing is known about the previous process's last read, so the restore counts as activity:
    // the timer asks at max(L, min(restore + I, N)) + grace.
    let restoredAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let now = LockedBox(restoredAt)
    let keychain = InMemoryKeychain()
    let projectId = "proj_\(UUID().uuidString)"
    let signer = MockCredentialSigner()
    let expiry = restoredAt.addingTimeInterval(2 * day)
    try storeSessionRecord(
        keychain: keychain,
        projectId: projectId,
        signer: signer,
        expiresAt: expiry,
        fields: [
            "idleWindowSeconds": 10 * day,
            "expiryCeilingEpochSeconds": restoredAt.timeIntervalSince1970 + 100 * day,
        ]
    )

    let fixture = makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now.withValue { $0 } },
        prepareTransport: { transport in
            transport.enqueueTransportError(
                WebRPCTransportError(message: "The Internet connection appears to be offline."),
                for: WaasAPI.GetCredential.urlPath
            )
        }
    )
    #expect(fixture.client.activeWallet?.id == "wallet-main")
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    try await waitForCredentialRefreshToFinish(fixture.client)
    #expect(fixture.client.withSessionLock { fixture.client._lastCredentialRefreshAt } == nil)

    let checkDate = restoredAt.addingTimeInterval(10 * day + grace)
    now.withValue { $0 = expiry.addingTimeInterval(grace + 1) }
    try await expectTimerDefers(fixture.client, to: checkDate)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.activeWallet?.id == "wallet-main")

    now.withValue { $0 = checkDate.addingTimeInterval(1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 2)
}

@Test @MainActor func TestExpiryTimerAddsSlideDampeningWhenBoundsAreUnknown() async throws {
    // A sign-in whose credential expiry is not after its send gives no idle window, so the timer
    // waits L + max(0, A - C) + 6 hours + grace.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: signInAt)
    #expect(fixture.client.withSessionLock { fixture.client._sessionExpiryBounds } == nil)

    let checkDate = signInAt.addingTimeInterval(WalletClient.serverExpirySlideDampeningSeconds + grace)
    now.withValue { $0 = signInAt.addingTimeInterval(grace + 1) }
    try await expectTimerDefers(fixture.client, to: checkDate)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    now.withValue { $0 = checkDate.addingTimeInterval(1) }
    try await expectTimerEndsSession(fixture, getCredentialCount: 1)
}

@Test @MainActor func TestExpiryTimerBoundUsesRequestCompletionTime() async throws {
    // A request that stalls before reaching WaaS moves the expiry as late as its completion.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    let gate = fixture.transport.holdResponses(for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xsigned"), for: WaasAPI.SignMessage.urlPath)

    now.withValue { $0 = signInAt.addingTimeInterval(hour) }
    let client = fixture.client
    let sign = Task { try await client.signMessage(network: .polygon, message: "hello") }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 1 }
    let completedAt = signInAt.addingTimeInterval(3 * hour)
    now.withValue { $0 = completedAt }
    gate.open()
    #expect(try await sign.value == "0xsigned")

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: completedAt.addingTimeInterval(10 * day + grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

@Test @MainActor func TestExpiryTimerTreatsSlowSuccessfulReadAsLastRead() async throws {
    // A read that completes later than it was sent, with nothing sent after it: its completion is
    // both the last read and the last activity, so the timer asks right after the returned expiry.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let expiry = signInAt.addingTimeInterval(10 * day)
    try await signIn(fixture, lifetimeSeconds: WalletClient.maxSessionLifetimeSeconds, expiresAt: expiry)
    let gate = fixture.transport.holdResponses(for: WaasAPI.GetCredential.urlPath)
    try fixture.transport.enqueue(credentialResponse(expiresAt: isoTimestamp(expiry)), for: WaasAPI.GetCredential.urlPath)

    now.withValue { $0 = signInAt.addingTimeInterval(hour) }
    let client = fixture.client
    let refresh = Task { await client.refreshCredentialExpiry() }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    now.withValue { $0 = signInAt.addingTimeInterval(2 * hour) }
    gate.open()
    guard case .refreshed = await refresh.value else {
        Issue.record("Expected the read to succeed")
        return
    }

    now.withValue { $0 = expiry.addingTimeInterval(1) }
    try await expectTimerDefers(fixture.client, to: expiry.addingTimeInterval(grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

enum SignInPath: CaseIterable, Sendable {
    case email, oidcIdToken, oidcRedirect, manualSelection
}

@Test(arguments: SignInPath.allCases)
@MainActor func TestEverySignInPathKeepsAndPersistsExpiryBounds(_ path: SignInPath) async throws {
    // I = L0 - C0 and N = max(C0 + R, L0), from the CompleteAuth exchange of each sign-in path.
    let signInAt = Date(timeIntervalSince1970: 1_767_225_600)
    let now = LockedBox(signInAt)
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    let lifetime = UInt32(12 * day)
    let wallet = testWallet(id: "wallet-main", address: "0x2222222222222222222222222222222222222222")
    let completeAuth = completeAuthResponse(
        identity: path == .email || path == .manualSelection
            ? Identity(type: .email, sub: "user@example.com")
            : Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
        wallets: [wallet],
        credential: WaasCredentialInfo(
            credentialId: "0xcredential",
            type: .direct,
            expiresAt: isoTimestamp(signInAt.addingTimeInterval(10 * day)),
            isCaller: true
        )
    )
    if path == .oidcIdToken || path == .oidcRedirect {
        try fixture.transport.enqueue(
            CommitVerifierResponse(verifier: "oidc-verifier", loginHint: "", challenge: "pkce-challenge"),
            for: WaasAPI.CommitVerifier.urlPath
        )
    }
    try fixture.transport.enqueue(completeAuth, for: WaasAPI.CompleteAuth.urlPath)
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)

    switch path {
    case .email:
        fixture.client.pendingEmailAuth = PendingEmailAuth(email: "user@example.com", sessionLifetimeSeconds: lifetime)
        _ = try await fixture.client.completeEmailAuth(code: "123456")
    case .oidcIdToken:
        _ = try await fixture.client.signInWithOidcIdToken(
            idToken: try fakeOidcIdToken(),
            issuer: "https://accounts.google.com",
            audience: "demo-web-client-id",
            sessionLifetimeSeconds: lifetime
        )
    case .oidcRedirect:
        let started = try await fixture.client.startOIDCRedirectAuth(
            provider: CustomOIDCProviderConfiguration(
                issuer: "https://issuer.example",
                clientID: "client-123",
                authorizationURL: "https://issuer.example/oauth/authorize",
                providerRedirectURI: "omsclientswiftdemo://auth/callback"
            ),
            sessionLifetimeSeconds: lifetime
        )
        _ = try await fixture.client.handleOIDCRedirectCallback(
            "omsclientswiftdemo://auth/callback?code=auth-code&state=\(try oidcState(started))"
        )
    case .manualSelection:
        fixture.client.pendingEmailAuth = PendingEmailAuth(email: "user@example.com", sessionLifetimeSeconds: lifetime)
        let result = try await fixture.client.completeEmailAuth(code: "123456", walletSelection: .manual)
        guard case .walletSelection(let selection) = result else {
            Issue.record("Expected a pending wallet selection")
            return
        }
        // The values come from the sign-in, not from when the selection completes.
        now.withValue { $0 = signInAt.addingTimeInterval(hour) }
        _ = try await selection.selectWallet(walletId: wallet.id)
    }

    let expected = SessionExpiryBounds(
        idleWindowSeconds: 10 * day,
        ceilingEpochSeconds: signInAt.addingTimeInterval(12 * day).timeIntervalSince1970
    )
    #expect(fixture.client.activeWallet?.id == "wallet-main")
    #expect(fixture.client.withSessionLock { fixture.client._sessionExpiryBounds } == expected)
    #expect(try fixture.storedCredentials()?.expiryBounds == expected)

    // Sign-out drops them.
    try fixture.client.signOut()
    #expect(fixture.client.withSessionLock { fixture.client._sessionExpiryBounds } == nil)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestSessionExpiryBoundsFromSignIn() throws {
    let sentAt = Date(timeIntervalSince1970: 1_767_225_600)
    // Lifetime shorter than the idle window: the expiry is the ceiling.
    let short = try #require(
        SessionExpiryBounds(signInSentAt: sentAt, expiresAt: "2026-01-01T01:00:00Z", requestedLifetimeSeconds: 3_600)
    )
    #expect(short.idleWindowSeconds == 3_600)
    #expect(short.ceiling == sentAt.addingTimeInterval(3_600))
    // The server raises a lifetime under 1 minute; N is never below L0.
    let clamped = try #require(
        SessionExpiryBounds(signInSentAt: sentAt, expiresAt: "2026-01-01T00:01:00Z", requestedLifetimeSeconds: 1)
    )
    #expect(clamped.ceiling == sentAt.addingTimeInterval(60))
    #expect(SessionExpiryBounds(signInSentAt: sentAt, expiresAt: "not-a-date", requestedLifetimeSeconds: 60) == nil)
    #expect(SessionExpiryBounds(signInSentAt: sentAt, expiresAt: "2026-01-01T00:00:00Z", requestedLifetimeSeconds: 60) == nil)
}

// MARK: - Restore read waits for the foreground

/// Stands in for app activation: holds the work the client asks to run when active.
private final class ForegroundTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () -> Void] = []

    func runWhenActive(_ body: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(body)
    }

    func activate() {
        lock.lock()
        let bodies = pending
        pending = []
        lock.unlock()
        bodies.forEach { $0() }
    }
}

/// Restores a session stored with a 10-day idle window, expiring 2 days after `restoredAt`.
private func makeRestoredFixture(
    restoredAt: Date,
    now: LockedBox<Date>,
    trigger: ForegroundTrigger,
    prepareTransport: (MockWaasTransport) throws -> Void = { _ in }
) throws -> MockWalletClientFixture {
    let keychain = InMemoryKeychain()
    let projectId = "proj_\(UUID().uuidString)"
    let signer = MockCredentialSigner()
    try storeSessionRecord(
        keychain: keychain,
        projectId: projectId,
        signer: signer,
        expiresAt: restoredAt.addingTimeInterval(2 * day),
        fields: [
            "idleWindowSeconds": 10 * day,
            "expiryCeilingEpochSeconds": restoredAt.timeIntervalSince1970 + 100 * day,
        ]
    )
    return makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now.withValue { $0 } },
        runWhenActive: trigger.runWhenActive,
        prepareTransport: prepareTransport
    )
}

@Test @MainActor func TestRestoreReadWaitsForAppActivationAndRestoreStillCountsAsActivity() async throws {
    // A background launch must not extend an idle session, so the restore read waits.
    let restoredAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let expiry = restoredAt.addingTimeInterval(2 * day)
    let now = LockedBox(restoredAt)
    let trigger = ForegroundTrigger()
    let serverExpiry = restoredAt.addingTimeInterval(12 * day)
    let fixture = try makeRestoredFixture(restoredAt: restoredAt, now: now, trigger: trigger) { transport in
        try transport.enqueue(credentialResponse(expiresAt: isoTimestamp(serverExpiry)), for: WaasAPI.GetCredential.urlPath)
    }
    #expect(fixture.client.activeWallet?.id == "wallet-main")
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    // Without the read, the restore still counts as activity at the restore time.
    now.withValue { $0 = expiry.addingTimeInterval(grace + 1) }
    try await expectTimerDefers(fixture.client, to: restoredAt.addingTimeInterval(10 * day + grace))
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    trigger.activate()
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    try await waitForCredentialRefreshToFinish(fixture.client)
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
    #expect(fixture.client.session?.expiresAt == isoTimestamp(serverExpiry))
}

@Test(arguments: [false, true])
@MainActor func TestRestoreReadIsSkippedWhenSessionChangesBeforeActivation(_ signsInAgain: Bool) async throws {
    let restoredAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let now = LockedBox(restoredAt)
    let trigger = ForegroundTrigger()
    let fixture = try makeRestoredFixture(restoredAt: restoredAt, now: now, trigger: trigger)
    #expect(fixture.client.activeWallet?.id == "wallet-main")

    try fixture.client.signOut()
    if signsInAgain {
        fixture.client.verifier = "verifier"
        fixture.client.challenge = "challenge"
        fixture.client.pendingEmailAuth = PendingEmailAuth(email: "user@example.com", sessionLifetimeSeconds: 604_800)
        try await signIn(fixture, expiresAt: restoredAt.addingTimeInterval(10 * day))
        #expect(fixture.client.activeWallet?.id == "wallet-main")
    }
    trigger.activate()
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

@Test func TestForegroundActivationRunsOnceOnNextNotification() async throws {
    let center = NotificationCenter()
    let name = Notification.Name("TestDidBecomeActive")
    let runs = LockedBox(0)
    ForegroundActivation.runOnce(onNext: name, in: center) { runs.withValue { $0 += 1 } }
    #expect(runs.withValue { $0 } == 0)

    center.post(name: name, object: nil)
    center.post(name: name, object: nil)

    #expect(runs.withValue { $0 } == 1)
}

// MARK: - Timer scheduling, activation metadata, and 7207 reads

@Test func TestZeroDelayExpiryTimerKeepsTheTimerItReschedules() throws {
    // A zero-delay timer can run before its scheduling returns. Each fire here defers to L + grace;
    // the deferral's timer must survive, with its fire date, whatever the interleaving. The race is
    // narrow, so the test repeats it.
    let expiry = Date(timeIntervalSince1970: 1_767_225_600).addingTimeInterval(10 * day)
    let now = LockedBox(expiry.addingTimeInterval(1))
    let fixture = makeMockWalletClient(currentDate: { now.withValue { $0 } })
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: isoTimestamp(expiry)
    )
    let client = fixture.client
    let checkDate = expiry.addingTimeInterval(grace)

    var lostTimers = 0
    for _ in 0..<6_000 {
        try fireExpiryTimer(client)
        var isRescheduled = false
        for _ in 0..<1_000 where !isRescheduled {
            isRescheduled = isSameInstant(sessionExpiryTimerFireDate(client), checkDate)
                && client.withSessionLock { client.sessionExpiryTask?.isCancelled == false }
            if !isRescheduled {
                usleep(100)
            }
        }
        if !isRescheduled {
            lostTimers += 1
        }
    }

    #expect(lostTimers == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

@Test func TestExpiryTimerSchedulesFarFutureExpiryWithoutOverflow() throws {
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "9999-12-31T23:59:59Z"
    )
    let session = try #require(fixture.client.currentSessionSnapshot())

    fixture.client.scheduleSessionExpiry(session)

    #expect(isSameInstant(sessionExpiryTimerFireDate(fixture.client), session.expiryDate))
    #expect(fixture.client.withSessionLock { fixture.client.sessionExpiryTask != nil })
}

@Test @MainActor func TestWalletActivationKeepsExpiryReadWhileItWasInFlight() async throws {
    // useWallet captures the session metadata before its request, which waits behind the read.
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        expiresAt: "2098-01-01T00:00:00Z"
    )
    let laterExpiry = "2099-06-01T00:00:00Z"
    let readGate = fixture.transport.holdResponses(for: WaasAPI.GetCredential.urlPath)
    let useWalletGate = fixture.transport.holdResponses(for: WaasAPI.UseWallet.urlPath)
    try fixture.transport.enqueue(credentialResponse(expiresAt: laterExpiry), for: WaasAPI.GetCredential.urlPath)
    let other = testWallet(id: "wallet-other", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(UseWalletResponse(wallet: other), for: WaasAPI.UseWallet.urlPath)
    let client = fixture.client

    let refresh = Task { await client.refreshCredentialExpiry() }
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1 }
    let activation = Task { try await client.useWallet(walletId: "wallet-other") }
    try await Task.sleep(nanoseconds: 100_000_000)
    readGate.open()
    _ = await refresh.value
    #expect(client.session?.expiresAt == laterExpiry)
    try await waitUntil { fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 1 }
    useWalletGate.open()
    _ = try await activation.value

    #expect(client.activeWallet?.id == "wallet-other")
    #expect(client.session?.expiresAt == laterExpiry)
    #expect(try fixture.storedCredentials()?.expiresAt == laterExpiry)
    #expect(try fixture.storedCredentials()?.wallet.id == "wallet-other")
    #expect(try fixture.storedCredentials()?.expiryBounds == testExpiryBounds)
}

private let walletCallUnauthorizedBody = Data(
    #"{"error":"Unauthorized","code":7207,"msg":"Unauthorized","status":401}"#.utf8
)

@Test @MainActor func TestWalletCallUnauthorizedReadEndsRevokedSession() async throws {
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    )
    fixture.transport.enqueueRawHTTPError(statusCode: 401, body: walletCallUnauthorizedBody, for: WaasAPI.SignMessage.urlPath)
    fixture.transport.enqueueRawHTTPError(statusCode: 401, body: unauthorizedBody, for: WaasAPI.GetCredential.urlPath)
    var expiredEvents: [OMSWalletSessionExpiredEvent] = []
    let observation = fixture.client.addSessionExpiredObserver { expiredEvents.append($0) }
    defer { observation.cancel() }

    do {
        _ = try await fixture.client.signMessage(network: .polygon, message: "hello")
        Issue.record("Expected the wallet call's 7207")
    } catch let error as OMSWalletError {
        #expect(error.code == .requestFailed)
        #expect(error.upstreamError?.code == "7207")
    }
    try await waitUntil { !expiredEvents.isEmpty }

    #expect(expiredEvents.count == 1)
    #expect(fixture.client.session == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

@Test @MainActor func TestWalletCallUnauthorizedReadKeepsSessionWithAccess() async throws {
    // The credential is fine (the call lacked access to something else): the read only refreshes.
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    )
    fixture.transport.enqueueRawHTTPError(statusCode: 401, body: walletCallUnauthorizedBody, for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(credentialResponse(expiresAt: "2099-06-01T00:00:00Z"), for: WaasAPI.GetCredential.urlPath)

    _ = try? await fixture.client.signMessage(network: .polygon, message: "hello")
    try await waitUntil { fixture.client.session?.expiresAt == "2099-06-01T00:00:00Z" }
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(fixture.client.session?.expiresAt == "2099-06-01T00:00:00Z")
    #expect(fixture.client.activeWallet?.id == "wallet-main")
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}
