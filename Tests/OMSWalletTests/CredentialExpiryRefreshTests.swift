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
