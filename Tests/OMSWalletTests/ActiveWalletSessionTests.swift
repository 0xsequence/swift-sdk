import Foundation
import Testing
@testable import OMSWallet

private let testEnvironment = OMSWalletEnvironment(
    walletApiUrl: "https://wallet.example.test",
    indexerGatewayUrl: "https://indexer.example.test/v1/IndexerGateway/"
)

private func makeFixture(
    storedRecordJSON: String,
    projectId: String = "proj_\(UUID().uuidString)",
    currentDate: @escaping () -> Date = Date.init
) throws -> MockWalletClientFixture {
    let keychain = InMemoryKeychain()
    try keychain.set(
        storedRecordJSON,
        forKey: Constants.credentialsStorageKey(environment: testEnvironment, scope: projectId)
    )
    return makeMockWalletClient(
        environment: testEnvironment,
        projectId: projectId,
        keychain: keychain,
        currentDate: currentDate
    )
}

private func storedRecordJSON(version: Int = 2, walletJSON: String) -> String {
    """
    {"version":\(version),"wallet":\(walletJSON),"signerCredentialId":"0xmock-credential",\
    "alg":"ecdsa-p256-sha256","expiresAt":"2099-01-01T00:00:00Z",\
    "auth":{"type":"email","email":"user@example.com"}}
    """
}

@Test func TestActiveWalletAndSessionAreNilWhenSignedOut() throws {
    let fixture = makeMockWalletClient()

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
}

@Test func TestCompletedAuthDefinesActiveWalletAndSessionTogether() async throws {
    let fixture = makeMockWalletClient()
    let wallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(completeAuthResponse(wallets: [wallet]), for: WaasAPI.CompleteAuth.urlPath)
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)

    let result = try await fixture.client.completeEmailAuth(code: "123456")

    let expected = Wallet(
        id: "wallet-1",
        type: .ethereum,
        address: "0x1111111111111111111111111111111111111111",
        keyOrigin: .enclave
    )
    #expect(result.wallet == expected)
    #expect(fixture.client.activeWallet == expected)
    #expect(fixture.client.session?.expiresAt == "2099-01-01T00:00:00Z")
    #expect(fixture.client.session?.auth == .email(OMSWalletEmailSessionAuth(email: "user@example.com")))
    #expect(try fixture.storedCredentials()?.wallet == expected)

    try fixture.client.signOut()

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
}

@Test func TestRestoresStoredTronWalletWithItsType() throws {
    let fixture = try makeFixture(
        storedRecordJSON: storedRecordJSON(
            walletJSON: #"{"id":"wallet-tron","type":"tron","address":"TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL","reference":"main","keyOrigin":"imported"}"#
        )
    )

    #expect(
        fixture.client.activeWallet
            == Wallet(
                id: "wallet-tron",
                type: .tron,
                address: "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL",
                reference: "main",
                keyOrigin: .imported
            )
    )
    #expect(fixture.client.walletId == "wallet-tron")
    #expect(fixture.client.session?.auth.email == "user@example.com")
}

@Test func TestDiscardsVersionOneStoredSessionsOnLoad() throws {
    let projectId = "proj_\(UUID().uuidString)"
    let fixture = try makeFixture(
        storedRecordJSON: """
        {"walletId":"wallet-1","walletAddress":"0x1111111111111111111111111111111111111111",\
        "signerCredentialId":"0xmock-credential","alg":"ecdsa-p256-sha256",\
        "expiresAt":"2099-01-01T00:00:00Z","auth":{"type":"email","email":"user@example.com"}}
        """,
        projectId: projectId
    )

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(fixture.client.walletId == "")
    #expect(
        try fixture.keychain.string(
            forKey: Constants.credentialsStorageKey(environment: testEnvironment, scope: projectId)
        ) == nil
    )
}

@Test(arguments: [
    #"{"id":"wallet-1","type":"ethereum","address":"0xdef","keyOrigin":"enclave"}"#,
    #"{"id":"wallet-1","type":"bitcoin","address":"bc1q","keyOrigin":"enclave"}"#,
    #"{"id":"wallet-1","type":"tron","address":"TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL","keyOrigin":"derived"}"#
])
func TestDiscardsStoredSessionsWithInvalidWallets(walletJSON: String) throws {
    let fixture = try makeFixture(storedRecordJSON: storedRecordJSON(walletJSON: walletJSON))

    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestRejectsEthereumWalletResponsesWithNonHexAddresses() async throws {
    let fixture = makeMockWalletClient()
    fixture.client.activeWallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    fixture.client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    fixture.client.sessionAuth = .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: testWallet(id: "wallet-bad", address: "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL")),
        for: WaasAPI.UseWallet.urlPath
    )

    do {
        _ = try await fixture.client.useWallet(walletId: "wallet-bad")
        Issue.record("Expected an invalid wallet response")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .walletUseWallet)
        #expect(error.localizedDescription == "Ethereum wallet response has an invalid address")
    }
    #expect(fixture.client.activeWallet?.id == "wallet-main")
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestAcceptsMixedCaseEthereumWalletAddressesWithoutChecksumValidation() throws {
    let wallet = try Wallet(
        waasValue: WaasWallet(
            id: "wallet-1",
            networkFamily: .evm,
            keyOrigin: .enclave,
            address: "0xABCDEFabcdef0000000000000000000000000000"
        )
    )

    #expect(wallet.address == "0xABCDEFabcdef0000000000000000000000000000")
}

@Test func TestRejectsAuthResponsesWithUnreadableCredentialExpiry() async throws {
    let fixture = makeMockWalletClient()
    let wallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [wallet],
            credential: WaasCredentialInfo(
                credentialId: "0xcredential",
                type: .direct,
                expiresAt: "soon",
                isCaller: true
            )
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )

    do {
        _ = try await fixture.client.completeEmailAuth(code: "123456")
        Issue.record("Expected an invalid auth response")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .walletCompleteEmailAuth)
    }
    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(!fixture.signer.hasStoredCredential)
}

@Test(arguments: [
    WaasWallet(
        id: "wallet-1",
        networkFamily: .evm,
        keyOrigin: .unknown("derived"),
        address: "0x1111111111111111111111111111111111111111"
    ),
    WaasWallet(
        id: "wallet-1",
        networkFamily: .unknown("bitcoin"),
        keyOrigin: .enclave,
        address: "bc1q"
    ),
])
func TestSignInRejectsWalletsThatCannotBeRestored(wallet: WaasWallet) async throws {
    let fixture = makeMockWalletClient()
    let candidates = wallet.networkFamily == .evm ? [wallet] : []
    try fixture.transport.enqueue(completeAuthResponse(wallets: candidates), for: WaasAPI.CompleteAuth.urlPath)
    try fixture.transport.enqueue(UseWalletResponse(wallet: wallet), for: WaasAPI.UseWallet.urlPath)
    try fixture.transport.enqueue(CreateWalletResponse(wallet: wallet), for: WaasAPI.CreateWallet.urlPath)

    do {
        _ = try await fixture.client.completeEmailAuth(code: "123456")
        Issue.record("Expected an invalid wallet response")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .walletCompleteEmailAuth)
    }
    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(try fixture.storedCredentials() == nil)
}

@Test @MainActor func TestPendingWalletSelectionExpiryNotifiesWithoutWallet() async throws {
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_767_225_599)
    let fixture = makeMockWalletClient(currentDate: { now })
    let wallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
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
    var expiredEvent: OMSWalletSessionExpiredEvent?
    let observation = fixture.client.addSessionExpiredObserver { event in
        expiredEvent = event
    }
    defer { observation.cancel() }

    let result = try await fixture.client.completeEmailAuth(code: "123456", walletSelection: .manual)
    guard case .walletSelection(let pendingSelection) = result else {
        Issue.record("Expected a pending wallet selection")
        return
    }
    #expect(fixture.client.session == nil)

    now = Date(timeIntervalSince1970: 1_767_225_601)
    do {
        _ = try await pendingSelection.selectWallet(walletId: "wallet-1")
        Issue.record("Expected an expired session")
    } catch let error as OMSWalletError {
        #expect(error.code == .sessionExpired)
    }
    for _ in 0..<100 where expiredEvent == nil {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    let event = try #require(expiredEvent)
    #expect(event.wallet == nil)
    #expect(event.session.auth.email == "user@example.com")
    #expect(event.expiredAt == "2026-01-01T00:00:00Z")
    #expect(fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 0)
}
