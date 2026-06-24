import Foundation
import Testing
@testable import OMS_SDK

@Test func TestWalletCompleteEmailAuthManualReturnsPendingWalletSelection() async throws {
    let fixture = makeMockWalletClient()
    let availableWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let otherTypeWallet = testWallet(
        id: "wallet-2",
        type: .unknown("other"),
        address: "0x2222222222222222222222222222222222222222"
    )
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [availableWallet, otherTypeWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )

    switch result {
    case .walletSelection(let pendingSelection):
        #expect(pendingSelection.walletType == .ethereum)
        #expect(pendingSelection.wallets.map(\.id) == [availableWallet.id])
        #expect(pendingSelection.credential.credentialId == testCredential.credentialId)
    case .walletSelected:
        #expect(Bool(false))
    }

    let request = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasAPI.CompleteAuth.urlPath
    )
    #expect(request.verifier == "verifier")
    #expect(request.lifetime == 604_800)
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.session.walletAddress == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
}

@Test func TestWalletCompleteEmailAuthAutomaticSelectsFirstMatchingWallet() async throws {
    let fixture = makeMockWalletClient()
    let firstWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let secondWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let otherTypeWallet = testWallet(
        id: "wallet-3",
        type: .unknown("other"),
        address: "0x3333333333333333333333333333333333333333"
    )
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [firstWallet, secondWallet, otherTypeWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: firstWallet),
        for: WaasAPI.UseWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(code: "123456")
    guard case .walletSelected(_, let wallet, let wallets, _) = result else {
        #expect(Bool(false))
        return
    }

    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasAPI.UseWallet.urlPath
    )
    let storedCredentials = try fixture.storedCredentials()

    #expect(wallet.id == firstWallet.id)
    #expect(wallets.map(\.id) == [firstWallet.id, secondWallet.id, otherTypeWallet.id])
    #expect(useWalletRequest.walletId == firstWallet.id)
    #expect(fixture.client.walletId == firstWallet.id)
    #expect(fixture.client.walletAddress == firstWallet.address)
    #expect(fixture.client.session.walletAddress == firstWallet.address)
    #expect(storedCredentials?.walletId == firstWallet.id)
    #expect(storedCredentials?.walletAddress == firstWallet.address)
    #expect(storedCredentials?.loginType == .email)
    #expect(storedCredentials?.sessionEmail == "user@example.com")
}

@Test func TestWalletCompleteEmailAuthUsesCustomSessionLifetime() async throws {
    let fixture = makeMockWalletClient()
    let wallet = testWallet(id: "wallet-custom-lifetime", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [wallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: wallet),
        for: WaasAPI.UseWallet.urlPath
    )

    _ = try await fixture.client.completeEmailAuth(
        code: "123456",
        sessionLifetimeSeconds: 30
    )
    let completeAuthRequest = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasAPI.CompleteAuth.urlPath
    )

    #expect(completeAuthRequest.lifetime == 30)
}

@Test func TestWalletOperationExpiresSessionRetainsMetadataAndNotifiesDelegate() async throws {
    let expiresAt = "2026-01-01T00:00:00Z"
    var now = Date(timeIntervalSince1970: 1_767_225_599)
    let fixture = makeMockWalletClient(currentDate: { now })
    let wallet = testWallet(id: "wallet-expiring", address: "0x1111111111111111111111111111111111111111")
    let credential = CredentialInfo(
        credentialId: "0xcredential",
        expiresAt: expiresAt,
        isCaller: true
    )
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [wallet], credential: credential),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: wallet),
        for: WaasAPI.UseWallet.urlPath
    )

    _ = try await fixture.client.completeEmailAuth(code: "123456")
    var expiredEvent: SessionExpiredEvent?
    fixture.client.onSessionExpired = { event in
        expiredEvent = event
    }

    now = Date(timeIntervalSince1970: 1_767_225_601)
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.signMessage(network: .polygon, message: "hello")
    }

    let storedCredentials = try fixture.storedCredentials()
    #expect(expiredEvent?.session.walletAddress == wallet.address)
    #expect(expiredEvent?.session.expiresAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(expiredEvent?.session.loginType == .email)
    #expect(expiredEvent?.session.sessionEmail == "user@example.com")
    #expect(expiredEvent?.expiredAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(storedCredentials?.walletId == wallet.id)
    #expect(storedCredentials?.walletAddress == wallet.address)
    #expect(storedCredentials?.expiresAt == expiresAt)
    #expect(storedCredentials?.sessionEmail == "user@example.com")
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.SignMessage.urlPath) == 0)
}

@Test func TestWalletRestoredExpiredSessionIsInactiveAndReplaysDelegate() throws {
    let storedCredentials = StorableCredentials(
        walletId: "wallet-expired",
        walletAddress: "0x1111111111111111111111111111111111111111",
        signerCredentialId: "0xmock-credential",
        alg: .ecdsaP256Sha256,
        expiresAt: "2026-01-01T00:00:00Z",
        loginType: .email,
        sessionEmail: "user@example.com"
    )
    let fixture = makeMockWalletClient(
        currentDate: { Date(timeIntervalSince1970: 1_767_225_601) },
        storedCredentials: storedCredentials
    )
    var expiredEvent: SessionExpiredEvent?

    fixture.client.onSessionExpired = { event in
        expiredEvent = event
    }

    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(expiredEvent?.session.walletAddress == storedCredentials.walletAddress)
    #expect(expiredEvent?.session.sessionEmail == "user@example.com")
    #expect(expiredEvent?.expiredAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(try fixture.storedCredentials()?.walletId == storedCredentials.walletId)
    #expect(fixture.signer.clearCallCount == 1)
}

@Test func TestWalletRestoredActiveSessionSchedulesExpiryTimer() async throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expiresAt = Date().addingTimeInterval(0.05)
    let storedCredentials = StorableCredentials(
        walletId: "wallet-restored-expiring",
        walletAddress: "0x1111111111111111111111111111111111111111",
        signerCredentialId: "0xmock-credential",
        alg: .ecdsaP256Sha256,
        expiresAt: formatter.string(from: expiresAt),
        loginType: .email,
        sessionEmail: "user@example.com"
    )
    let fixture = makeMockWalletClient(storedCredentials: storedCredentials)
    var expiredEvent: SessionExpiredEvent?

    fixture.client.onSessionExpired = { event in
        expiredEvent = event
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(expiredEvent?.session.walletAddress == storedCredentials.walletAddress)
    #expect(expiredEvent?.session.sessionEmail == "user@example.com")
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(try fixture.storedCredentials()?.walletId == storedCredentials.walletId)
}

@Test func TestWalletSessionExpiryTimerNotifiesDelegate() async throws {
    let fixture = makeMockWalletClient(
        currentDate: { Date(timeIntervalSince1970: 1_767_225_601) }
    )
    let wallet = testWallet(id: "wallet-expired-timer", address: "0x2222222222222222222222222222222222222222")
    let credential = CredentialInfo(
        credentialId: "0xcredential",
        expiresAt: "2026-01-01T00:00:00Z",
        isCaller: true
    )
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [wallet], credential: credential),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: wallet),
        for: WaasAPI.UseWallet.urlPath
    )

    _ = try await fixture.client.completeEmailAuth(code: "123456")
    await Task.yield()
    await Task.yield()
    var expiredEvent: SessionExpiredEvent?
    fixture.client.onSessionExpired = { event in
        expiredEvent = event
    }

    #expect(expiredEvent?.session.walletAddress == wallet.address)
    #expect(expiredEvent?.session.sessionEmail == "user@example.com")
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(try fixture.storedCredentials()?.walletId == wallet.id)
}

@Test func TestWalletCompleteEmailAuthFetchesPaginatedWallets() async throws {
    let fixture = makeMockWalletClient()
    let firstWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let secondWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let thirdWallet = testWallet(id: "wallet-3", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [firstWallet], page: Page(cursor: "cursor-1")),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [secondWallet], page: Page(cursor: " cursor-2 ")),
        for: WaasAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [thirdWallet], page: Page(cursor: " ")),
        for: WaasAPI.ListWallets.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    let listWalletsRequests = try fixture.transport.decodedRequests(
        ListWalletsRequest.self,
        for: WaasAPI.ListWallets.urlPath
    )

    #expect(result.wallets.map(\.id) == [firstWallet.id, secondWallet.id, thirdWallet.id])
    #expect(listWalletsRequests.count == 2)
    #expect(listWalletsRequests[0].page?.cursor == "cursor-1")
    #expect(listWalletsRequests[1].page?.cursor == "cursor-2")
}

@Test func TestPendingWalletSelectionSelectsAndCreatesWallets() async throws {
    let selectFixture = makeMockWalletClient()
    let firstWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let selectedWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    try selectFixture.transport.enqueue(
        completeAuthResponse(wallets: [firstWallet, selectedWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try selectFixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasAPI.UseWallet.urlPath
    )

    let result = try await selectFixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    guard case .walletSelection(let pendingSelection) = result else {
        #expect(Bool(false))
        return
    }

    do {
        _ = try await pendingSelection.selectWallet(walletId: "wallet-missing")
        #expect(Bool(false))
    } catch let error as OmsSdkError {
        #expect(error.code == .walletSelectionUnavailable)
        #expect(error.operation == nil)
    } catch {
        #expect(Bool(false))
    }

    let selected = try await pendingSelection.selectWallet(walletId: selectedWallet.id)
    let useWalletRequest = try selectFixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasAPI.UseWallet.urlPath
    )

    #expect(selected.wallet.id == selectedWallet.id)
    #expect(useWalletRequest.walletId == selectedWallet.id)

    do {
        _ = try await pendingSelection.createAndSelectWallet(reference: "after-select")
        #expect(Bool(false))
    } catch let error as OmsSdkError {
        #expect(error.code == .walletSelectionStale)
        #expect(error.operation == nil)
    } catch {
        #expect(Bool(false))
    }
    #expect(selectFixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)

    let createFixture = makeMockWalletClient()
    let createdWallet = testWallet(id: "wallet-3", address: "0x3333333333333333333333333333333333333333")
    try createFixture.transport.enqueue(
        completeAuthResponse(wallets: []),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try createFixture.transport.enqueue(
        CreateWalletResponse(wallet: createdWallet),
        for: WaasAPI.CreateWallet.urlPath
    )

    let createResult = try await createFixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    guard case .walletSelection(let createPendingSelection) = createResult else {
        #expect(Bool(false))
        return
    }

    let created = try await createPendingSelection.createAndSelectWallet(reference: "reference-1")
    let createWalletRequest = try createFixture.transport.decodedRequest(
        CreateWalletRequest.self,
        for: WaasAPI.CreateWallet.urlPath
    )

    #expect(created.wallet.id == createdWallet.id)
    #expect(createWalletRequest.type == .ethereum)
    #expect(createWalletRequest.reference == "reference-1")
}

@Test func TestStalePendingWalletSelectionCannotCreateWalletAfterNewAuth() async throws {
    let fixture = makeMockWalletClient()
    let staleCreatedWallet = testWallet(id: "wallet-stale", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [], email: "first@example.com"),
        for: WaasAPI.CompleteAuth.urlPath
    )

    let firstResult = try await fixture.client.completeEmailAuth(
        code: "123456",
        walletSelection: .manual
    )
    guard case .walletSelection(let stalePendingSelection) = firstResult else {
        #expect(Bool(false))
        return
    }

    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "second-verifier",
            loginHint: "second@example.com",
            challenge: "second-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try await fixture.client.startEmailAuth(email: "second@example.com")
    _ = try fixture.signer.credentialId()
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [], email: "second@example.com"),
        for: WaasAPI.CompleteAuth.urlPath
    )

    let secondResult = try await fixture.client.completeEmailAuth(
        code: "654321",
        walletSelection: .manual
    )
    guard case .walletSelection = secondResult else {
        #expect(Bool(false))
        return
    }

    try fixture.transport.enqueue(
        CreateWalletResponse(wallet: staleCreatedWallet),
        for: WaasAPI.CreateWallet.urlPath
    )

    do {
        _ = try await stalePendingSelection.createAndSelectWallet(reference: "stale")
        #expect(Bool(false), "Stale pending wallet selection should not create and select a wallet after a newer auth flow")
    } catch let error as OmsSdkError {
        #expect(error.code == .walletSelectionStale)
        #expect(error.operation == nil)
        #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
        #expect(fixture.client.walletId == "")
        #expect(fixture.client.walletAddress == nil)
        #expect(try fixture.storedCredentials() == nil)
    } catch {
        #expect(Bool(false))
    }

    let storedCredentials = try fixture.storedCredentials()
    #expect(storedCredentials?.sessionEmail != "first@example.com")
}

@Test func TestWalletPublicUseCreateAndListWalletsUseVerifiedSession() async throws {
    let fixture = makeMockWalletClient()
    let existingWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let listedWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let createdWallet = testWallet(id: "wallet-3", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: []),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [existingWallet], page: Page(cursor: "next")),
        for: WaasAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [listedWallet], page: nil),
        for: WaasAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: existingWallet),
        for: WaasAPI.UseWallet.urlPath
    )
    try fixture.transport.enqueue(
        CreateWalletResponse(wallet: createdWallet),
        for: WaasAPI.CreateWallet.urlPath
    )

    _ = try await fixture.client.completeEmailAuth(code: "123456", walletSelection: .manual)
    let listedWallets = try await fixture.client.listWallets()
    let usedWallet = try await fixture.client.useWallet(walletId: existingWallet.id)
    let created = try await fixture.client.createWallet(
        walletType: .ethereum,
        reference: "reference-1"
    )

    let listWalletsRequests = try fixture.transport.decodedRequests(
        ListWalletsRequest.self,
        for: WaasAPI.ListWallets.urlPath
    )
    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasAPI.UseWallet.urlPath
    )
    let createWalletRequest = try fixture.transport.decodedRequest(
        CreateWalletRequest.self,
        for: WaasAPI.CreateWallet.urlPath
    )

    #expect(listedWallets.map(\.id) == [existingWallet.id, listedWallet.id])
    #expect(listWalletsRequests.count == 2)
    #expect(listWalletsRequests[0].page == nil)
    #expect(listWalletsRequests[1].page?.cursor == "next")
    #expect(useWalletRequest.walletId == existingWallet.id)
    #expect(usedWallet.wallet.id == existingWallet.id)
    #expect(createWalletRequest.type == .ethereum)
    #expect(createWalletRequest.reference == "reference-1")
    #expect(created.wallet.id == createdWallet.id)
    #expect(fixture.client.walletId == createdWallet.id)
    #expect(fixture.client.walletAddress == createdWallet.address)
    #expect(fixture.client.session.loginType == .email)
    #expect(fixture.client.session.sessionEmail == "user@example.com")
}

@Test func TestWalletCompleteEmailAuthSignsOutWhenActivationFails() async throws {
    let fixture = makeMockWalletClient()
    let existingWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [existingWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    fixture.transport.enqueueHTTPError(
        statusCode: 500,
        errorCode: WebRPCErrorKind.internalError.code,
        message: "activation failed",
        for: WaasAPI.UseWallet.urlPath
    )

    do {
        _ = try await fixture.client.completeEmailAuth(code: "123456")
        #expect(Bool(false))
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .walletCompleteEmailAuth)
        #expect(error.status == 500)
        #expect((error.underlyingError as? WebRPCError)?.code == WebRPCErrorKind.internalError.code)
    } catch {
        #expect(Bool(false))
    }

    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.verifier == "")
    #expect(fixture.client.challenge == "")
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.signer.hasStoredCredential == false)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestWalletSignInWithOidcIdTokenCommitsCompletesAndResolvesWallet() async throws {
    let fixture = makeMockWalletClient()
    let idToken = try fakeOidcIdToken()
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: ""
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(
                type: .oidc,
                iss: "https://accounts.google.com",
                sub: "google-sub-123"
            ),
            wallets: [selectedWallet],
            email: "user@example.com"
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasAPI.UseWallet.urlPath
    )

    let result = try await fixture.client.signInWithOidcIdToken(
        idToken: idToken,
        issuer: "https://accounts.google.com",
        audience: "demo-web-client-id"
    )
    guard case .walletSelected(_, let wallet, _, _) = result else {
        #expect(Bool(false))
        return
    }

    let commitRequest = try fixture.transport.decodedRequest(
        CommitVerifierRequest.self,
        for: WaasAPI.CommitVerifier.urlPath
    )
    let completeAuthRequest = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasAPI.CompleteAuth.urlPath
    )
    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasAPI.UseWallet.urlPath
    )
    let storedCredentials = try fixture.storedCredentials()

    #expect(commitRequest.identityType == .oidc)
    #expect(commitRequest.authMode == .idToken)
    #expect(commitRequest.metadata == [
        "iss": "https://accounts.google.com",
        "aud": "demo-web-client-id",
        "exp": "1910000100"
    ])
    #expect(commitRequest.handle == expectedOidcHandleHash(idToken))
    #expect(completeAuthRequest.identityType == .oidc)
    #expect(completeAuthRequest.authMode == .idToken)
    #expect(completeAuthRequest.verifier == "oidc-verifier-123")
    #expect(completeAuthRequest.answer == idToken)
    #expect(completeAuthRequest.lifetime == 604_800)
    #expect(useWalletRequest.walletId == selectedWallet.id)
    #expect(wallet.id == selectedWallet.id)
    #expect(fixture.client.walletId == selectedWallet.id)
    #expect(fixture.client.walletAddress == selectedWallet.address)
    #expect(fixture.client.session.loginType == .googleAuth)
    #expect(fixture.client.session.sessionEmail == "user@example.com")
    #expect(storedCredentials?.loginType == .googleAuth)
    #expect(storedCredentials?.sessionEmail == "user@example.com")
}

@Test func TestWalletSignInWithOidcIdTokenCanReturnManualWalletSelection() async throws {
    let fixture = makeMockWalletClient()
    let availableWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: ""
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [availableWallet],
            email: "user@example.com"
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )

    let result = try await fixture.client.signInWithOidcIdToken(
        idToken: try fakeOidcIdToken(),
        issuer: "https://issuer.example",
        audience: "demo-web-client-id",
        walletSelection: .manual
    )
    guard case .walletSelection(let pendingSelection) = result else {
        #expect(Bool(false))
        return
    }

    #expect(pendingSelection.walletType == .ethereum)
    #expect(pendingSelection.wallets.map(\.id) == [availableWallet.id])
    #expect(pendingSelection.credential.credentialId == testCredential.credentialId)
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.session.walletAddress == nil)
    #expect(try fixture.storedCredentials() == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
}

@Test func TestWalletSignInWithOidcIdTokenClearsPendingRedirectAuth() async throws {
    let fixture = makeMockWalletClient()
    try fixture.oidcRedirectAuthStore.save(
        PendingOidcRedirectAuth(
            verifier: "stale-verifier",
            challenge: "stale-challenge",
            nonce: "stale-nonce",
            redirectUri: "omssdkdemo://auth/callback",
            issuer: "https://issuer.example",
            authorizationScope: fixture.projectId,
            walletType: .ethereum,
            signerCredentialId: "0xmock-credential",
            signerKeyType: .ecdsaP256Sha256
        )
    )
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: ""
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://accounts.google.com", sub: "google-sub-123"),
            wallets: [selectedWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasAPI.UseWallet.urlPath
    )

    _ = try await fixture.client.signInWithOidcIdToken(
        idToken: try fakeOidcIdToken(),
        issuer: "https://accounts.google.com",
        audience: "demo-web-client-id"
    )

    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
}

@Test func TestWalletSignInWithOidcIdTokenSignsOutWhenCompleteAuthFails() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: ""
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    fixture.transport.enqueueHTTPError(
        statusCode: 500,
        errorCode: WebRPCErrorKind.identityProviderError.code,
        message: "identity provider error",
        for: WaasAPI.CompleteAuth.urlPath
    )

    do {
        _ = try await fixture.client.signInWithOidcIdToken(
            idToken: try fakeOidcIdToken(),
            issuer: "https://accounts.google.com",
            audience: "demo-web-client-id"
        )
        #expect(Bool(false))
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .walletSignInWithOidcIdToken)
        #expect(error.status == 500)
        #expect((error.underlyingError as? WebRPCError)?.code == WebRPCErrorKind.identityProviderError.code)
    } catch {
        #expect(Bool(false))
    }

    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.verifier == "")
    #expect(fixture.client.challenge == "")
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(fixture.signer.hasStoredCredential == false)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestWalletStartOidcRedirectAuthCommitsVerifierBuildsAuthorizationUrlAndStoresPendingAuth() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    let provider = OidcProviderConfig(
        issuer: "https://issuer.example",
        clientId: "client-123",
        authorizationUrl: "https://issuer.example/oauth/authorize",
        relayRedirectUri: "https://relay.example/callback",
        authorizeParams: ["prompt": "consent"]
    )

    let result = try await fixture.client.startOidcRedirectAuth(
        provider: provider,
        redirectUri: "omssdkdemo://auth/callback",
        authorizeParams: ["prompt": "select_account", "audience": "wallet"]
    )
    let request = try fixture.transport.decodedRequest(
        CommitVerifierRequest.self,
        for: WaasAPI.CommitVerifier.urlPath
    )
    let query = queryParams(result.authorizationUrl)
    let decodedState = try decodedOidcState(result.state)

    #expect(request.identityType == .oidc)
    #expect(request.authMode == .authCodePkce)
    #expect(request.metadata["iss"] == "https://issuer.example")
    #expect(request.metadata["aud"] == "client-123")
    #expect(request.metadata["redirect_uri"] == "https://relay.example/callback")
    #expect(uriOriginAndPath(result.authorizationUrl) == "https://issuer.example/oauth/authorize")
    #expect(query["client_id"] == "client-123")
    #expect(query["redirect_uri"] == "https://relay.example/callback")
    #expect(query["response_type"] == "code")
    #expect(query["scope"] == "openid email profile")
    #expect(query["state"] == result.state)
    #expect(query["code_challenge"] == "pkce-challenge")
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["login_hint"] == nil)
    #expect(query["prompt"] == "select_account")
    #expect(query["audience"] == "wallet")
    #expect(decodedState["nonce"] as? String == "nonce-123")
    #expect(decodedState["scope"] as? String == fixture.projectId)
    #expect(decodedState["redirect_uri"] as? String == "omssdkdemo://auth/callback")
    #expect(result.challenge == "pkce-challenge")
    #expect(fixture.oidcRedirectAuthStore.pending?.verifier == "oidc-verifier-123")
    #expect(fixture.oidcRedirectAuthStore.pending?.challenge == "pkce-challenge")
    #expect(fixture.oidcRedirectAuthStore.pending?.nonce == "nonce-123")
    #expect(fixture.oidcRedirectAuthStore.pending?.redirectUri == "omssdkdemo://auth/callback")
    #expect(fixture.oidcRedirectAuthStore.pending?.walletType == .ethereum)
    #expect(fixture.oidcRedirectAuthStore.pending?.signerCredentialId == "0xmock-credential")
    #expect(fixture.oidcRedirectAuthStore.pending?.signerKeyType == .ecdsaP256Sha256)
    #expect(fixture.client.canResumeOidcRedirectAuth)
    #expect(fixture.client.verifier == "oidc-verifier-123")
}

@Test func TestWalletStartOidcRedirectAuthUsesStoredEmailAsGoogleLoginHint() async throws {
    let storedCredentials = StorableCredentials(
        walletId: "wallet-google",
        walletAddress: "0x1111111111111111111111111111111111111111",
        signerCredentialId: "0xmock-credential",
        alg: .ecdsaP256Sha256,
        expiresAt: "2099-01-01T00:00:00Z",
        loginType: .googleAuth,
        sessionEmail: "last@example.com"
    )
    let fixture = makeMockWalletClient(
        oidcNonceGenerator: { "nonce-123" },
        currentDate: { Date(timeIntervalSince1970: 1_767_225_599) },
        storedCredentials: storedCredentials
    )
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )

    let result = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviders.google(relayRedirectUri: nil),
        redirectUri: "omssdkdemo://auth/callback"
    )
    let query = queryParams(result.authorizationUrl)

    #expect(query["login_hint"] == "last@example.com")
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestWalletHandleOidcRedirectCallbackCompletesAuthActivatesWalletAndClearsPendingAuth() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    let secondWallet = testWallet(id: "wallet-ghi", address: "0xghi")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet, secondWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasAPI.UseWallet.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?code=auth-code&state=\(started.state)&scope=openid"
    )
    guard case .completed(let wallet) = result else {
        #expect(Bool(false))
        return
    }
    let completeAuthRequest = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasAPI.CompleteAuth.urlPath
    )
    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasAPI.UseWallet.urlPath
    )
    let storedCredentials = try fixture.storedCredentials()

    #expect(completeAuthRequest.identityType == .oidc)
    #expect(completeAuthRequest.authMode == .authCodePkce)
    #expect(completeAuthRequest.verifier == "oidc-verifier-123")
    #expect(completeAuthRequest.answer == "auth-code")
    #expect(completeAuthRequest.lifetime == 604_800)
    #expect(useWalletRequest.walletId == selectedWallet.id)
    #expect(wallet.address == "0xdef")
    #expect(fixture.client.walletAddress == "0xdef")
    #expect(fixture.client.walletId == "wallet-def")
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
    #expect(storedCredentials?.walletId == "wallet-def")
    #expect(storedCredentials?.walletAddress == "0xdef")
    #expect(storedCredentials?.loginType == .oidc)
    #expect(storedCredentials?.sessionEmail == "user@example.com")
}

@Test func TestWalletHandleOidcRedirectCallbackCompletesAuthFromFragmentResponseMode() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-fragment", address: "0xfragment")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasAPI.UseWallet.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback",
        authorizeParams: ["response_mode": "fragment"]
    )

    #expect(queryParams(started.authorizationUrl)["response_mode"] == "fragment")
    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback#code=fragment-code&state=\(started.state)&scope=openid"
    )
    guard case .completed(let wallet) = result else {
        #expect(Bool(false))
        return
    }
    let completeAuthRequest = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasAPI.CompleteAuth.urlPath
    )

    #expect(completeAuthRequest.answer == "fragment-code")
    #expect(wallet.id == selectedWallet.id)
    #expect(fixture.client.walletId == selectedWallet.id)
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
}

@Test func TestWalletHandleOidcRedirectCallbackCanReturnPendingWalletSelectionWithoutActivatingWallet() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    let otherTypeWallet = testWallet(
        id: "wallet-other",
        type: .unknown("other"),
        address: "0xother"
    )
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet, otherTypeWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?code=auth-code&state=\(started.state)",
        walletSelection: .manual
    )

    guard case .walletSelection(let pendingSelection) = result else {
        #expect(Bool(false))
        return
    }
    #expect(pendingSelection.walletType == .ethereum)
    #expect(pendingSelection.wallets.map(\.id) == ["wallet-def"])
    #expect(pendingSelection.credential.credentialId == testCredential.credentialId)
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.session.walletAddress == nil)
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 0)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestWalletHandleOidcRedirectCallbackIgnoresUnrelatedCallbackWithoutClearingPendingAuth() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "otherapp://auth/callback?code=auth-code&state=\(started.state)"
    )

    guard case .notOidcRedirectCallback = result else {
        #expect(Bool(false))
        return
    }
    #expect(fixture.client.canResumeOidcRedirectAuth)
    #expect(fixture.oidcRedirectAuthStore.pending?.verifier == "oidc-verifier-123")
    #expect(fixture.transport.requestCount(for: WaasAPI.CompleteAuth.urlPath) == 0)
}

@Test func TestWalletHandleOidcRedirectCallbackIgnoresInvalidStateWithoutClearingPendingAuth() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    _ = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?code=auth-code&state=not-base64"
    )

    guard case .notOidcRedirectCallback = result else {
        #expect(Bool(false))
        return
    }
    #expect(fixture.client.canResumeOidcRedirectAuth)
    #expect(fixture.oidcRedirectAuthStore.pending?.verifier == "oidc-verifier-123")
    #expect(fixture.transport.requestCount(for: WaasAPI.CompleteAuth.urlPath) == 0)
}

@Test func TestWalletHandleOidcRedirectCallbackKeepsPendingAuthWhenCancelled() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    fixture.transport.enqueueCancellation(for: WaasAPI.UseWallet.urlPath)
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    do {
        _ = try await fixture.client.handleOidcRedirectCallback(
            "omssdkdemo://auth/callback?code=auth-code&state=\(started.state)"
        )
        #expect(Bool(false))
        return
    } catch is CancellationError {
    } catch {
        #expect(Bool(false))
    }
    #expect(fixture.client.canResumeOidcRedirectAuth)
    #expect(fixture.oidcRedirectAuthStore.pending?.verifier == "oidc-verifier-123")
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.signer.clearCallCount == 1)
    #expect(fixture.signer.hasStoredCredential)
}

@Test func TestWalletHandleOidcRedirectCallbackReturnsFailedAndClearsPendingAuthForProviderError() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasAPI.CommitVerifier.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = try await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?error=access_denied&error_description=User%20cancelled&state=\(started.state)"
    )

    guard case .failed(let error as OmsSdkError) = result else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .validationError)
    #expect(error.operation == .walletHandleOidcRedirectCallback)
    #expect(error.underlyingError as? OidcRedirectAuthError == .providerError("User cancelled"))
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == nil)
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
}

@Test func TestWalletPublicMethodsRequireActiveWalletBeforeUsingWalletState() async throws {
    let fixture = makeMockWalletClient()

    await expectNoAuthenticatedWalletSession {
        try await fixture.client.listAccess()
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.listAccessPage()
    }
    await expectNoAuthenticatedWalletSession {
        var iterator = fixture.client.listAccessPages().makeAsyncIterator()
        _ = try await iterator.next()
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.getIdToken()
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.revokeAccess(targetCredentialId: "credential-1")
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.signMessage(network: .polygonAmoy, message: "hello")
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.signTypedData(network: .polygonAmoy, typedData: .object([:]))
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.isValidMessageSignature(
            network: .polygonAmoy,
            walletAddress: "0xwallet",
            message: "hello",
            signature: "0xsig"
        )
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.isValidTypedDataSignature(
            network: .polygonAmoy,
            walletAddress: "0xwallet",
            typedData: .object([:]),
            signature: "0xsig"
        )
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.sendTransaction(
            network: .polygonAmoy,
            to: "0xabc",
            value: "0"
        )
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.sendTransaction(
            network: .polygonAmoy,
            request: SendTransactionRequest(to: "0xabc", value: "0")
        )
    }
    await expectNoAuthenticatedWalletSession {
        try await fixture.client.callContract(
            network: .polygonAmoy,
            contract: "0xcontract",
            method: "mint(address)",
            args: nil
        )
    }

    let blockedPaths = [
        WaasAPI.ListAccess.urlPath,
        WaasAPI.GetIDToken.urlPath,
        WaasAPI.RevokeAccess.urlPath,
        WaasAPI.SignMessage.urlPath,
        WaasAPI.SignTypedData.urlPath,
        WaasPublicAPI.IsValidMessageSignature.urlPath,
        WaasPublicAPI.IsValidTypedDataSignature.urlPath,
        WaasAPI.PrepareEthereumTransaction.urlPath,
        WaasAPI.PrepareEthereumContractCall.urlPath
    ]
    for path in blockedPaths {
        #expect(fixture.transport.requestCount(for: path) == 0)
    }

    let walletIdOnlyFixture = makeMockWalletClient()
    walletIdOnlyFixture.client.walletId = "wallet-main"
    await expectNoAuthenticatedWalletSession {
        try await walletIdOnlyFixture.client.sendTransaction(
            network: .polygonAmoy,
            to: "0xabc",
            value: "0",
            selectFeeOption: .firstAvailable
        )
    }
    await expectNoAuthenticatedWalletSession {
        try await walletIdOnlyFixture.client.callContract(
            network: .polygonAmoy,
            contract: "0xcontract",
            method: "mint(address)",
            args: nil,
            selectFeeOption: .firstAvailable
        )
    }
    #expect(walletIdOnlyFixture.transport.requestCount(for: WaasAPI.PrepareEthereumTransaction.urlPath) == 0)
    #expect(walletIdOnlyFixture.transport.requestCount(for: WaasAPI.PrepareEthereumContractCall.urlPath) == 0)
}

@Test func TestWalletListAccessPaginationHelpersUseWaasPages() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    let firstCredential = CredentialInfo(
        credentialId: "credential-1",
        expiresAt: "2026-01-01T00:00:00Z",
        isCaller: true
    )
    let secondCredential = CredentialInfo(
        credentialId: "credential-2",
        expiresAt: "2026-01-02T00:00:00Z",
        isCaller: false
    )
    let manualCredential = CredentialInfo(
        credentialId: "credential-3",
        expiresAt: "2026-01-03T00:00:00Z",
        isCaller: false
    )

    try fixture.transport.enqueue(
        ListAccessResponse(credentials: [firstCredential], page: Page(cursor: "next")),
        for: WaasAPI.ListAccess.urlPath
    )
    try fixture.transport.enqueue(
        ListAccessResponse(credentials: [secondCredential]),
        for: WaasAPI.ListAccess.urlPath
    )
    try fixture.transport.enqueue(
        ListAccessResponse(credentials: [manualCredential], page: Page(cursor: "after-manual")),
        for: WaasAPI.ListAccess.urlPath
    )

    var pages: [ListAccessResponse] = []
    for try await page in fixture.client.listAccessPages(pageSize: 1) {
        pages.append(page)
    }
    let manualPage = try await fixture.client.listAccessPage(pageSize: 2, cursor: "manual")
    let listAccessRequests = try fixture.transport.decodedRequests(
        ListAccessRequest.self,
        for: WaasAPI.ListAccess.urlPath
    )

    #expect(pages.count == 2)
    #expect(pages[0].credentials.map(\.credentialId) == ["credential-1"])
    #expect(pages[0].page?.cursor == "next")
    #expect(pages[1].credentials.map(\.credentialId) == ["credential-2"])
    #expect(pages[1].page?.cursor == nil)
    #expect(manualPage.credentials.map(\.credentialId) == ["credential-3"])
    #expect(manualPage.page?.cursor == "after-manual")
    #expect(listAccessRequests.count == 3)
    #expect(listAccessRequests[0].walletId == "wallet-main")
    #expect(listAccessRequests[0].page?.limit == 1)
    #expect(listAccessRequests[0].page?.cursor == nil)
    #expect(listAccessRequests[1].walletId == "wallet-main")
    #expect(listAccessRequests[1].page?.limit == 1)
    #expect(listAccessRequests[1].page?.cursor == "next")
    #expect(listAccessRequests[2].walletId == "wallet-main")
    #expect(listAccessRequests[2].page?.limit == 2)
    #expect(listAccessRequests[2].page?.cursor == "manual")
}

@Test func TestWalletListAccessReturnsCombinedCredentialPages() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        ListAccessResponse(
            credentials: [
                CredentialInfo(
                    credentialId: "credential-1",
                    expiresAt: "2026-01-01T00:00:00Z",
                    isCaller: true
                )
            ],
            page: Page(cursor: "next")
        ),
        for: WaasAPI.ListAccess.urlPath
    )
    try fixture.transport.enqueue(
        ListAccessResponse(
            credentials: [
                CredentialInfo(
                    credentialId: "credential-2",
                    expiresAt: "2026-01-02T00:00:00Z",
                    isCaller: false
                )
            ]
        ),
        for: WaasAPI.ListAccess.urlPath
    )

    let credentials = try await fixture.client.listAccess(pageSize: 25)
    let listAccessRequests = try fixture.transport.decodedRequests(
        ListAccessRequest.self,
        for: WaasAPI.ListAccess.urlPath
    )

    #expect(credentials.map(\.credentialId) == ["credential-1", "credential-2"])
    #expect(listAccessRequests.count == 2)
    #expect(listAccessRequests[0].page?.limit == 25)
    #expect(listAccessRequests[0].page?.cursor == nil)
    #expect(listAccessRequests[1].page?.limit == 25)
    #expect(listAccessRequests[1].page?.cursor == "next")
}

@Test func TestWalletSendTransactionDefaultSelectsFirstFeeOptionIdentifierWithoutBalanceLookup() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .executed, txnHash: "0xdeadbeef"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        to: "0xabc",
        value: "0"
    )
    let prepareRequest = try fixture.transport.decodedRequest(
        PrepareEthereumTransactionRequest.self,
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    let executeRequest = try fixture.transport.decodedRequest(
        ExecuteRequest.self,
        for: WaasAPI.Execute.urlPath
    )

    #expect(txResult.txnId == "txn-1")
    #expect(txResult.status == .executed)
    #expect(txResult.txnHash == "0xdeadbeef")
    #expect(prepareRequest.mode == .relayer)
    #expect(executeRequest.feeOption?.token == "POL")
    #expect(fixture.indexerClient.nativeBalanceRequestCount == 0)
    #expect(fixture.indexerClient.tokenBalanceContractAddresses.isEmpty)
}

@Test func TestWalletGetTransactionStatusKeepsCancellationError() async throws {
    let fixture = makeMockWalletClient()
    fixture.transport.enqueueCancellation(for: WaasAPI.TransactionStatusMethod.urlPath)

    do {
        _ = try await fixture.client.getTransactionStatus(txnId: "txn-cancelled-1")
        #expect(Bool(false), "Expected CancellationError")
    } catch is CancellationError {
    } catch {
        #expect(Bool(false), "Expected CancellationError")
    }
}

@Test func TestWalletSendTransactionFirstAvailableSelectsFirstFundedFeeOption() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"
    fixture.indexerClient.setNativeBalance(
        TokenBalance(
            contractType: "NATIVE",
            contractAddress: nil,
            accountAddress: "0xwallet",
            tokenId: nil,
            balance: "99",
            blockHash: nil,
            blockNumber: nil,
            chainId: 80002
        )
    )
    fixture.indexerClient.setTokenBalances(
        [
            TokenBalance(
                contractType: "ERC20",
                contractAddress: "0xUSDC",
                accountAddress: "0xwallet",
                tokenId: nil,
                balance: "20",
                blockHash: nil,
                blockNumber: nil,
                chainId: 80002
            )
        ],
        for: "0xusdc"
    )

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .executed, txnHash: "0xdeadbeef"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        to: "0xabc",
        value: "0",
        selectFeeOption: .firstAvailable
    )
    let executeRequest = try fixture.transport.decodedRequest(
        ExecuteRequest.self,
        for: WaasAPI.Execute.urlPath
    )

    #expect(txResult.txnId == "txn-1")
    #expect(txResult.status == .executed)
    #expect(executeRequest.feeOption?.token == "usdc")
    #expect(fixture.indexerClient.nativeBalanceRequestCount == 1)
    #expect(fixture.indexerClient.tokenBalanceContractAddresses == ["0xusdc"])
}

@Test func TestWalletSendTransactionFirstAvailableRequiresFundedFeeOption() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"
    fixture.indexerClient.setNativeBalance(
        TokenBalance(
            contractType: "NATIVE",
            contractAddress: nil,
            accountAddress: "0xwallet",
            tokenId: nil,
            balance: "99",
            blockHash: nil,
            blockNumber: nil,
            chainId: 80002
        )
    )
    fixture.indexerClient.setTokenBalances(
        [
            TokenBalance(
                contractType: "ERC20",
                contractAddress: "0xUSDC",
                accountAddress: "0xwallet",
                tokenId: nil,
                balance: "19",
                blockHash: nil,
                blockNumber: nil,
                chainId: 80002
            )
        ],
        for: "0xusdc"
    )

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )

    do {
        _ = try await fixture.client.sendTransaction(
            network: .polygonAmoy,
            to: "0xabc",
            value: "0",
            selectFeeOption: .firstAvailable
        )
    } catch let error as OmsSdkError {
        #expect(error.code == .validationError)
        #expect(error.operation == .walletSendTransaction)
        #expect(isTransactionError(error.underlyingError, .noFeeOptionSelected))
        #expect(fixture.indexerClient.nativeBalanceRequestCount == 1)
        #expect(fixture.indexerClient.tokenBalanceContractAddresses == ["0xusdc"])
        #expect(fixture.transport.requestCount(for: WaasAPI.Execute.urlPath) == 0)
        return
    }
    #expect(Bool(false), "Expected TransactionError.noFeeOptionSelected")
}

@Test func TestFeeOptionSelectorFirstAvailableRejectsMalformedAvailableRaw() async throws {
    let feeOption = testFeeOptions()[0]

    let selection = try await FeeOptionSelector.firstAvailable([
        FeeOptionWithBalance(
            feeOption: feeOption,
            availableRaw: "not-a-number"
        )
    ])

    #expect(selection == nil)
}

@Test func TestFeeOptionSelectorFirstAvailableRejectsMalformedFeeValue() async throws {
    let baseFeeOption = testFeeOptions()[0]
    let malformedFeeOption = FeeOption(
        token: baseFeeOption.token,
        value: "not-a-number",
        displayValue: "invalid"
    )

    let selection = try await FeeOptionSelector.firstAvailable([
        FeeOptionWithBalance(
            feeOption: malformedFeeOption,
            availableRaw: "100000"
        )
    ])

    #expect(selection == nil)
}

@Test func TestFeeOptionSelectorFirstAvailableAcceptsValidUnsignedDecimals() async throws {
    let feeOption = testFeeOptions()[0]

    let selection = try await FeeOptionSelector.firstAvailable([
        FeeOptionWithBalance(
            feeOption: feeOption,
            availableRaw: "000100"
        )
    ])

    #expect(selection?.token == FeeOptionWithBalance(feeOption: feeOption).selection.token)
}

@Test func TestWalletSendTransactionCustomSelectorReceivesFeeOptionBalances() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"
    fixture.indexerClient.setNativeBalance(
        TokenBalance(
            contractType: "NATIVE",
            contractAddress: nil,
            accountAddress: "0xwallet",
            tokenId: nil,
            balance: "100",
            blockHash: nil,
            blockNumber: nil,
            chainId: 80002
        )
    )
    fixture.indexerClient.setTokenBalances(
        [
            TokenBalance(
                contractType: "ERC20",
                contractAddress: "0xUSDC",
                accountAddress: "0xwallet",
                tokenId: nil,
                balance: "2000",
                blockHash: nil,
                blockNumber: nil,
                chainId: 80002
            )
        ],
        for: "0xusdc"
    )

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .executed, txnHash: "0xdeadbeef"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0", mode: .native),
        selectFeeOption: .custom { feeOptions in
            #expect(feeOptions.count == 2)
            #expect(feeOptions[0].feeOption.token.symbol == "POL")
            #expect(feeOptions[0].balance?.balance == "100")
            #expect(feeOptions[0].available == "0.0000000000000001")
            #expect(feeOptions[0].availableRaw == "100")
            #expect(feeOptions[0].decimals == 18)
            #expect(feeOptions[1].feeOption.token.symbol == "USDC")
            #expect(feeOptions[1].balance?.balance == "2000")
            #expect(feeOptions[1].available == "0.002")
            #expect(feeOptions[1].availableRaw == "2000")
            #expect(feeOptions[1].decimals == 6)
            return feeOptions[1].selection
        }
    )
    let prepareRequest = try fixture.transport.decodedRequest(
        PrepareEthereumTransactionRequest.self,
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    let executeRequest = try fixture.transport.decodedRequest(
        ExecuteRequest.self,
        for: WaasAPI.Execute.urlPath
    )

    #expect(txResult.txnId == "txn-1")
    #expect(txResult.status == .executed)
    #expect(txResult.txnHash == "0xdeadbeef")
    #expect(prepareRequest.mode == .native)
    #expect(executeRequest.feeOption?.token == "usdc")
    #expect(fixture.indexerClient.nativeBalanceRequestCount == 1)
    #expect(fixture.indexerClient.tokenBalanceContractAddresses == ["0xusdc"])
}

@Test func TestWalletSendTransactionUnsponsoredCustomSelectorRequiresSelection() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )

    do {
        _ = try await fixture.client.sendTransaction(
            network: .polygonAmoy,
            request: SendTransactionRequest(to: "0xabc", value: "0"),
            selectFeeOption: .custom { _ in nil }
        )
        #expect(Bool(false), "Expected no fee option selected error")
    } catch let error as OmsSdkError {
        #expect(error.code == .validationError)
        #expect(error.operation == .walletSendTransaction)
        #expect(isTransactionError(error.underlyingError, .noFeeOptionSelected))
    } catch {
        #expect(Bool(false), "Expected TransactionError.noFeeOptionSelected")
    }

    #expect(fixture.transport.requestCount(for: WaasAPI.Execute.urlPath) == 0)
}

@Test func TestWalletSendTransactionSponsoredSkipsCustomFeeSelector() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .executed),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0"),
        selectFeeOption: .custom { feeOptions in
            #expect(Bool(false), "Sponsored transactions should not ask for fee selection")
            return feeOptions.first?.selection
        }
    )
    let executeRequest = try fixture.transport.decodedRequest(
        ExecuteRequest.self,
        for: WaasAPI.Execute.urlPath
    )

    #expect(txResult.txnId == "txn-1")
    #expect(txResult.status == .executed)
    #expect(txResult.txnHash == nil)
    #expect(executeRequest.feeOption == nil)
    #expect(fixture.indexerClient.nativeBalanceRequestCount == 0)
    #expect(fixture.indexerClient.tokenBalanceContractAddresses.isEmpty)
}

@Test func TestWalletCallContractReturnsSendTransactionResponse() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-contract-1",
            status: .quoted,
            feeOptions: testFeeOptions(),
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumContractCall.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .executed, txnHash: "0xcontractdeadbeef"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.callContract(
        network: .polygonAmoy,
        contract: "0xcontract",
        method: "mint(address)",
        args: [AbiArg(type: "address", value: .string("0xrecipient"))],
        mode: .native
    )
    let prepareRequest = try fixture.transport.decodedRequest(
        PrepareEthereumContractCallRequest.self,
        for: WaasAPI.PrepareEthereumContractCall.urlPath
    )
    let executeRequest = try fixture.transport.decodedRequest(
        ExecuteRequest.self,
        for: WaasAPI.Execute.urlPath
    )

    #expect(txResult.txnId == "txn-contract-1")
    #expect(txResult.status == .executed)
    #expect(txResult.txnHash == "0xcontractdeadbeef")
    #expect(prepareRequest.mode == .native)
    #expect(executeRequest.txnId == "txn-contract-1")
    #expect(executeRequest.feeOption?.token == "POL")
}

@Test func TestWalletSendTransactionCanSkipStatusPolling() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-no-poll-1",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0"),
        waitForStatus: false
    )

    #expect(txResult.txnId == "txn-no-poll-1")
    #expect(txResult.status == .pending)
    #expect(txResult.txnHash == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 0)
}

@Test func TestWalletCallContractCanSkipStatusPolling() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-contract-no-poll-1",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumContractCall.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )

    let txResult = try await fixture.client.callContract(
        network: .polygonAmoy,
        contract: "0xcontract",
        method: "mint(address)",
        args: [AbiArg(type: "address", value: .string("0xrecipient"))],
        waitForStatus: false
    )

    #expect(txResult.txnId == "txn-contract-no-poll-1")
    #expect(txResult.status == .pending)
    #expect(txResult.txnHash == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 0)
}

@Test func TestWalletSendTransactionReturnsPendingResponseWhenPollingDelayIsZero() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-pending-1",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .pending),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0"),
        statusPolling: TransactionStatusPollingOptions(
            intervalMs: 0,
            fastIntervalMs: 0,
            fastPollCount: 0
        )
    )

    #expect(txResult.txnId == "txn-pending-1")
    #expect(txResult.status == .pending)
    #expect(txResult.txnHash == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 1)
}

@Test func TestWalletSendTransactionReturnsWhenPollingFindsHashBeforeExecuted() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-hash-1",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .pending, txnHash: "0xsubmitted"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0")
    )

    #expect(txResult.txnId == "txn-hash-1")
    #expect(txResult.status == .pending)
    #expect(txResult.txnHash == "0xsubmitted")
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 1)
}

@Test func TestWalletSendTransactionReturnsFailedStatusAsTerminal() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-failed",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .pending),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .failed),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0")
    )

    #expect(txResult.txnId == "txn-failed")
    #expect(txResult.status == .failed)
    #expect(txResult.txnHash == nil)
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 1)
}

@Test func TestWalletSendTransactionExecutedFastPathAcceptsStatusHash() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-fast-hash-1",
            status: .quoted,
            feeOptions: [],
            sponsored: true,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )
    try fixture.transport.enqueue(
        ExecuteResponse(status: .executed),
        for: WaasAPI.Execute.urlPath
    )
    try fixture.transport.enqueue(
        TransactionStatusResponse(status: .pending, txnHash: "0xfastsubmitted"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let txResult = try await fixture.client.sendTransaction(
        network: .polygonAmoy,
        request: SendTransactionRequest(to: "0xabc", value: "0")
    )

    #expect(txResult.txnId == "txn-fast-hash-1")
    #expect(txResult.status == .pending)
    #expect(txResult.txnHash == "0xfastsubmitted")
    #expect(fixture.transport.requestCount(for: WaasAPI.TransactionStatusMethod.urlPath) == 1)
}

@Test func TestWalletSendTransactionUnsponsoredWithoutFeeOptionsThrows() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-main"
    fixture.client.walletAddress = "0xwallet"

    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-1",
            status: .quoted,
            feeOptions: [],
            sponsored: false,
            expiresAt: "2026-04-27T00:00:00Z"
        ),
        for: WaasAPI.PrepareEthereumTransaction.urlPath
    )

    do {
        _ = try await fixture.client.sendTransaction(
            network: .polygonAmoy,
            request: SendTransactionRequest(to: "0xabc", value: "0")
        )
        #expect(Bool(false), "Expected no fee options error")
    } catch let error as OmsSdkError {
        #expect(error.code == .validationError)
        #expect(error.operation == .walletSendTransaction)
        #expect(isTransactionError(error.underlyingError, .noFeeOptionsAvailable))
    } catch {
        #expect(Bool(false), "Expected TransactionError.noFeeOptionsAvailable")
    }

    #expect(fixture.transport.requestCount(for: WaasAPI.Execute.urlPath) == 0)
}

private let testCredential = CredentialInfo(
    credentialId: "0xcredential",
    expiresAt: "2099-01-01T00:00:00Z",
    isCaller: true
)

private func expectNoAuthenticatedWalletSession<T>(
    _ operation: () async throws -> T
) async {
    do {
        _ = try await operation()
        #expect(Bool(false), "Expected no authenticated wallet session error")
    } catch let error as OmsSdkError {
        #expect(error.code == .sessionMissing)
        #expect(error.operation != nil)
    } catch {
        #expect(Bool(false), "Expected OmsSdkError.sessionMissing")
    }
}

private func isTransactionError(_ error: (any Error)?, _ expected: TransactionError) -> Bool {
    guard let transactionError = error as? TransactionError else {
        return false
    }

    switch (transactionError, expected) {
    case (.noFeeOptionsAvailable, .noFeeOptionsAvailable),
         (.noFeeOptionSelected, .noFeeOptionSelected),
         (.missingTransactionHash, .missingTransactionHash),
         (.pollingTimedOut, .pollingTimedOut):
        return true
    case (.transactionFailed(let actual), .transactionFailed(let expected)):
        return actual == expected
    default:
        return false
    }
}

private struct MockWalletClientFixture {
    let client: WalletClient
    let transport: MockWaasTransport
    let signer: MockCredentialSigner
    let keychain: InMemoryKeychain
    let environment: OMSClientEnvironment
    let projectId: String
    let oidcRedirectAuthStore: InMemoryOidcRedirectAuthStore
    let indexerClient: MockWalletIndexerClient

    func storedCredentials() throws -> StorableCredentials? {
        guard let json = try keychain.string(
            forKey: Constants.credentialsStorageKey(environment: environment, scope: projectId)
        ) else {
            return nil
        }
        return try StorableCredentials.from(jsonString: json)
    }
}

private func makeMockWalletClient(
    environment: OMSClientEnvironment = OMSClientEnvironment(
        walletApiUrl: "https://wallet.example.test"
    ),
    projectId: String = "proj_\(UUID().uuidString)",
    keychain: InMemoryKeychain = InMemoryKeychain(),
    signer: MockCredentialSigner = MockCredentialSigner(),
    oidcNonceGenerator: @escaping () throws -> String = OidcRedirectAuth.generateNonce,
    currentDate: @escaping () -> Date = Date.init,
    storedCredentials: StorableCredentials? = nil
) -> MockWalletClientFixture {
    let transport = MockWaasTransport()
    let indexerClient = MockWalletIndexerClient()
    let oidcRedirectAuthStore = InMemoryOidcRedirectAuthStore()
    if let storedCredentials {
        _ = try? keychain.set(
            storedCredentials.jsonString(),
            forKey: Constants.credentialsStorageKey(environment: environment, scope: projectId)
        )
    }
    let credentialSession = WalletCredentialSession(
        environment: environment,
        projectId: projectId,
        keychain: keychain,
        signerFactory: { _, _, _ in signer }
    )
    let signedClient = WaasClient(
        baseURL: environment.walletApiUrl,
        transport: transport
    )
    let publicClient = WaasPublicClient(
        baseURL: environment.walletApiUrl,
        transport: transport
    )
    let client = WalletClient(
        publishableKey: "test-publishable-key",
        projectId: projectId,
        environment: environment,
        credentialSession: credentialSession,
        signedClient: signedClient,
        publicClient: publicClient,
        indexerClient: indexerClient,
        oidcRedirectAuthStore: oidcRedirectAuthStore,
        oidcNonceGenerator: oidcNonceGenerator,
        currentDate: currentDate
    )
    client.verifier = "verifier"
    client.challenge = "challenge"

    return MockWalletClientFixture(
        client: client,
        transport: transport,
        signer: signer,
        keychain: keychain,
        environment: environment,
        projectId: projectId,
        oidcRedirectAuthStore: oidcRedirectAuthStore,
        indexerClient: indexerClient
    )
}

private func completeAuthResponse(
    identity: Identity = Identity(type: .email, sub: "user@example.com"),
    wallets: [Wallet],
    page: Page? = nil,
    email: String? = "user@example.com",
    credential: CredentialInfo = testCredential
) -> CompleteAuthResponse {
    CompleteAuthResponse(
        identity: identity,
        wallets: wallets,
        page: page,
        email: email,
        credential: credential
    )
}

private func testWallet(
    id: String,
    type: WalletType = .ethereum,
    address: String
) -> Wallet {
    Wallet(
        id: id,
        type: type,
        address: address
    )
}

private func testFeeOptions() -> [FeeOption] {
    [
        FeeOption(
            token: FeeToken(
                network: "polygon",
                name: "Polygon",
                symbol: "POL",
                type: "native",
                decimals: nil,
                logoUrl: "",
                contractAddress: nil,
                tokenId: nil
            ),
            value: "100",
            displayValue: "0.0000000000000001"
        ),
        FeeOption(
            token: FeeToken(
                network: "polygon",
                name: "USD Coin",
                symbol: "USDC",
                type: "erc20",
                decimals: 6,
                logoUrl: "",
                contractAddress: "0xUSDC",
                tokenId: "usdc"
            ),
            value: "20",
            displayValue: "0.002"
        )
    ]
}

private final class MockWalletIndexerClient: WalletIndexerClient, @unchecked Sendable {
    private let lock = NSLock()
    private var nativeBalance: TokenBalance?
    private var tokenBalancesByContract: [String: [TokenBalance]] = [:]
    private var balanceRequests: [GetBalancesParams] = []

    var nativeBalanceRequestCount: Int {
        withLock { balanceRequests.count }
    }

    var tokenBalanceContractAddresses: [String] {
        withLock {
            balanceRequests.flatMap { request in
                request.contractAddresses?.map { $0.lowercased() } ?? []
            }
        }
    }

    func setNativeBalance(_ balance: TokenBalance?) {
        withLock {
            nativeBalance = balance
        }
    }

    func setTokenBalances(_ balances: [TokenBalance], for contractAddress: String) {
        withLock {
            tokenBalancesByContract[contractAddress.lowercased()] = balances
        }
    }

    func getBalances(_ params: GetBalancesParams) async throws -> BalancesResult {
        withLock {
            balanceRequests.append(params)
            let tokenBalances = (params.contractAddresses ?? []).flatMap { contractAddress in
                tokenBalancesByContract[contractAddress.lowercased()] ?? []
            }
            return BalancesResult(
                status: 200,
                page: nil,
                nativeBalances: nativeBalance.map { [$0] } ?? [],
                balances: tokenBalances
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func uriOriginAndPath(_ url: String) -> String {
    guard let components = URLComponents(string: url) else {
        return ""
    }
    let scheme = components.scheme.map { "\($0)://" } ?? ""
    let host = components.host ?? ""
    let port = components.port.map { ":\($0)" } ?? ""
    return "\(scheme)\(host)\(port)\(components.percentEncodedPath)"
}

private func queryParams(_ url: String) -> [String: String] {
    guard let query = URLComponents(string: url)?.percentEncodedQuery else {
        return [:]
    }
    return query
        .split(separator: "&", omittingEmptySubsequences: true)
        .reduce(into: [String: String]()) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = urlDecode(String(parts[0]))
            let value = parts.count > 1 ? urlDecode(String(parts[1])) : ""
            result[key] = value
        }
}

private func decodedOidcState(_ value: String) throws -> [String: Any] {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: padding))
    let data = try #require(Data(base64Encoded: base64))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func urlDecode(_ value: String) -> String {
    value
        .replacingOccurrences(of: "+", with: " ")
        .removingPercentEncoding ?? value
}

private final class InMemoryKeychain: KeychainManaging {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    @discardableResult
    func set(_ value: String, forKey key: String, service: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[storageKey(key: key, service: service)] = value
        return true
    }

    func string(forKey key: String, service: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[storageKey(key: key, service: service)]
    }

    @discardableResult
    func delete(forKey key: String, service: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.removeValue(forKey: storageKey(key: key, service: service)) != nil
    }

    private func storageKey(key: String, service: String) -> String {
        "\(service):\(key)"
    }
}

private final class InMemoryOidcRedirectAuthStore: OidcRedirectAuthStore, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pending: PendingOidcRedirectAuth?

    func load() throws -> PendingOidcRedirectAuth? {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    func save(_ pending: PendingOidcRedirectAuth) throws {
        lock.lock()
        defer { lock.unlock() }
        self.pending = pending
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        pending = nil
    }
}

private final class MockCredentialSigner: CredentialSigner, @unchecked Sendable {
    let alg: SigningAlgorithm = .ecdsaP256Sha256

    private let lock = NSLock()
    private var credentialAvailable = true
    private var clearCalls = 0

    var hasStoredCredential: Bool {
        lock.lock()
        defer { lock.unlock() }
        return credentialAvailable
    }

    var clearCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return clearCalls
    }

    func credentialId() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        credentialAvailable = true
        return "0xmock-credential"
    }

    func nextNonce() throws -> String {
        "1"
    }

    func sign(preimage: String) throws -> String {
        "0xmock-signature"
    }

    func hasCredential() throws -> Bool {
        hasStoredCredential
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        credentialAvailable = false
        clearCalls += 1
    }
}

private struct RecordedWebRPCRequest: Sendable {
    let path: String
    let body: Data
}

private enum MockWaasResponse: Sendable {
    case success(Data)
    case httpError(statusCode: Int, body: Data)
    case failure(WebRPCTransportError)
    case cancellation
}

private final class MockWaasTransport: WebRPCTransport, @unchecked Sendable {
    enum MockError: Error {
        case unexpectedRequest(String)
        case missingRecordedRequest(String, Int)
    }

    private let lock = NSLock()
    private var responses: [String: [MockWaasResponse]] = [:]
    private var recordedRequests: [RecordedWebRPCRequest] = []

    func enqueue<T: Encodable>(_ response: T, for path: String) throws {
        let body = try WebRPCJSON.makeEncoder().encode(response)
        lock.lock()
        defer { lock.unlock() }
        responses[path, default: []].append(.success(body))
    }

    func enqueueHTTPError(
        statusCode: Int,
        errorCode: Int,
        message: String,
        for path: String
    ) {
        let body = Data(
            """
            {"error":"Internal","code":\(errorCode),"msg":"\(message)","cause":"test","status":\(statusCode)}
            """.utf8
        )
        lock.lock()
        defer { lock.unlock() }
        responses[path, default: []].append(.httpError(statusCode: statusCode, body: body))
    }

    func enqueueCancellation(for path: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[path, default: []].append(.cancellation)
    }

    func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let response = try recordAndDequeue(
            path: path,
            body: body
        )

        switch response {
        case .success(let body):
            return WebRPCHTTPResponse(statusCode: 200, body: body)
        case .httpError(let statusCode, let body):
            return WebRPCHTTPResponse(statusCode: statusCode, body: body)
        case .failure(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }

    private func recordAndDequeue(
        path: String,
        body: Data
    ) throws -> MockWaasResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(
            RecordedWebRPCRequest(
                path: path,
                body: body
            )
        )
        guard var queuedResponses = responses[path], !queuedResponses.isEmpty else {
            throw MockError.unexpectedRequest(path)
        }
        let response = queuedResponses.removeFirst()
        responses[path] = queuedResponses
        return response
    }

    func requestCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.filter { $0.path == path }.count
    }

    func decodedRequest<T: Decodable>(
        _ type: T.Type,
        for path: String,
        at index: Int = 0
    ) throws -> T {
        let requests = recordedRequests(for: path)
        guard requests.indices.contains(index) else {
            throw MockError.missingRecordedRequest(path, index)
        }
        return try WebRPCJSON.makeDecoder().decode(T.self, from: requests[index].body)
    }

    func decodedRequests<T: Decodable>(
        _ type: T.Type,
        for path: String
    ) throws -> [T] {
        try recordedRequests(for: path).map {
            try WebRPCJSON.makeDecoder().decode(T.self, from: $0.body)
        }
    }

    private func recordedRequests(for path: String) -> [RecordedWebRPCRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.filter { $0.path == path }
    }
}
