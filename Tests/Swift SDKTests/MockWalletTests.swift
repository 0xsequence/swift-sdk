import Foundation
import Testing
@testable import OMS_SDK

@Test func TestWalletCompleteEmailAuthAutoActivateFalseReturnsWalletSelection() async throws {
    let fixture = makeMockWalletClient()
    let availableWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [availableWallet]),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(
        code: "123456",
        autoActivate: false
    )

    switch result {
    case .walletSelection(let wallets, let credential):
        #expect(wallets.count == 1)
        #expect(wallets[0].id == availableWallet.id)
        #expect(credential.credentialId == testCredential.credentialId)
    case .activated:
        #expect(Bool(false))
    }

    let request = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    #expect(request.verifier == "verifier")
    #expect(request.lifetime == 604_800)
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == "")
    #expect(fixture.client.session.walletAddress == nil)
    #expect(fixture.transport.requestCount(for: WaasWalletAPI.UseWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasWalletAPI.CreateWallet.urlPath) == 0)
}

@Test func TestWalletCompleteEmailAuthSelectsFromMultipleWallets() async throws {
    let fixture = makeMockWalletClient()
    let firstWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let selectedWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let otherTypeWallet = testWallet(
        id: "wallet-3",
        type: .unknown("other"),
        address: "0x3333333333333333333333333333333333333333"
    )
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [firstWallet, selectedWallet, otherTypeWallet]),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasWalletAPI.UseWallet.urlPath
    )

    let activated = try await fixture.client.completeEmailAuth(code: "123456") { wallets in
        #expect(wallets.map(\.id) == [firstWallet.id, selectedWallet.id])
        return wallets[1]
    }

    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasWalletAPI.UseWallet.urlPath
    )
    let storedCredentials = try fixture.storedCredentials()

    #expect(activated.id == selectedWallet.id)
    #expect(useWalletRequest.walletId == selectedWallet.id)
    #expect(fixture.client.walletId == selectedWallet.id)
    #expect(fixture.client.walletAddress == selectedWallet.address)
    #expect(fixture.client.session.walletAddress == selectedWallet.address)
    #expect(storedCredentials?.walletId == selectedWallet.id)
    #expect(storedCredentials?.walletAddress == selectedWallet.address)
    #expect(storedCredentials?.loginType == .email)
    #expect(storedCredentials?.sessionEmail == "user@example.com")
}

@Test func TestWalletCompleteEmailAuthFetchesPaginatedWallets() async throws {
    let fixture = makeMockWalletClient()
    let firstWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let secondWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let thirdWallet = testWallet(id: "wallet-3", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [firstWallet], page: Page(cursor: "cursor-1")),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [secondWallet], page: Page(cursor: " cursor-2 ")),
        for: WaasWalletAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [thirdWallet], page: Page(cursor: " ")),
        for: WaasWalletAPI.ListWallets.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(
        code: "123456",
        autoActivate: false
    )
    let listWalletsRequests = try fixture.transport.decodedRequests(
        ListWalletsRequest.self,
        for: WaasWalletAPI.ListWallets.urlPath
    )

    #expect(result.wallets.map(\.id) == [firstWallet.id, secondWallet.id, thirdWallet.id])
    #expect(listWalletsRequests.count == 2)
    #expect(listWalletsRequests[0].page?.cursor == "cursor-1")
    #expect(listWalletsRequests[1].page?.cursor == "cursor-2")
}

@Test func TestWalletPublicUseCreateAndListWalletsUseVerifiedSession() async throws {
    let fixture = makeMockWalletClient()
    let existingWallet = testWallet(id: "wallet-1", address: "0x1111111111111111111111111111111111111111")
    let listedWallet = testWallet(id: "wallet-2", address: "0x2222222222222222222222222222222222222222")
    let createdWallet = testWallet(id: "wallet-3", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: []),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [existingWallet], page: Page(cursor: "next")),
        for: WaasWalletAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        ListWalletsResponse(wallets: [listedWallet], page: nil),
        for: WaasWalletAPI.ListWallets.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: existingWallet),
        for: WaasWalletAPI.UseWallet.urlPath
    )
    try fixture.transport.enqueue(
        CreateWalletResponse(wallet: createdWallet),
        for: WaasWalletAPI.CreateWallet.urlPath
    )

    _ = try await fixture.client.completeEmailAuth(code: "123456", autoActivate: false)
    let listedWallets = try await fixture.client.listWallets()
    let usedWallet = try await fixture.client.useWallet(walletId: existingWallet.id)
    let created = try await fixture.client.createWallet(
        walletType: .ethereum,
        reference: "reference-1"
    )

    let listWalletsRequests = try fixture.transport.decodedRequests(
        ListWalletsRequest.self,
        for: WaasWalletAPI.ListWallets.urlPath
    )
    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasWalletAPI.UseWallet.urlPath
    )
    let createWalletRequest = try fixture.transport.decodedRequest(
        CreateWalletRequest.self,
        for: WaasWalletAPI.CreateWallet.urlPath
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
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    fixture.transport.enqueueHTTPError(
        statusCode: 500,
        errorCode: WebRPCErrorKind.internalError.code,
        message: "activation failed",
        for: WaasWalletAPI.UseWallet.urlPath
    )

    do {
        _ = try await fixture.client.completeEmailAuth(code: "123456")
        #expect(Bool(false))
    } catch let error as WebRPCError {
        #expect(error.code == WebRPCErrorKind.internalError.code)
    } catch {
        #expect(Bool(false))
    }

    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == "")
    #expect(fixture.client.verifier == "")
    #expect(fixture.client.challenge == "")
    #expect(fixture.client.session == SessionState(walletAddress: nil))
    #expect(fixture.signer.clearCallCount == 1)
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
        for: WaasWalletAPI.CommitVerifier.urlPath
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
        for: WaasWalletAPI.CommitVerifier.urlPath
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
    #expect(query["login_hint"] == "user@example.com")
    #expect(query["prompt"] == "select_account")
    #expect(query["audience"] == "wallet")
    #expect(decodedState["nonce"] as? String == "nonce-123")
    #expect(decodedState["scope"] as? String == fixture.environment.scope)
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

@Test func TestWalletHandleOidcRedirectCallbackCompletesAuthActivatesWalletAndClearsPendingAuth() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasWalletAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet]
        ),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: selectedWallet),
        for: WaasWalletAPI.UseWallet.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?code=auth-code&state=\(started.state)&scope=openid"
    )
    guard case .completed(let wallet) = result else {
        #expect(Bool(false))
        return
    }
    let completeAuthRequest = try fixture.transport.decodedRequest(
        CompleteAuthRequest.self,
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    let useWalletRequest = try fixture.transport.decodedRequest(
        UseWalletRequest.self,
        for: WaasWalletAPI.UseWallet.urlPath
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

@Test func TestWalletHandleOidcRedirectCallbackCanReturnWalletSelectionWithoutActivatingWallet() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    let selectedWallet = testWallet(id: "wallet-def", address: "0xdef")
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasWalletAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://issuer.example", sub: "oidc-sub-123"),
            wallets: [selectedWallet]
        ),
        for: WaasWalletAPI.CompleteAuth.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?code=auth-code&state=\(started.state)",
        autoActivate: false
    )

    guard case .walletSelection(let wallets, let credential) = result else {
        #expect(Bool(false))
        return
    }
    #expect(wallets.map(\.id) == ["wallet-def"])
    #expect(credential.credentialId == testCredential.credentialId)
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == "")
    #expect(fixture.client.session.walletAddress == nil)
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
    #expect(fixture.transport.requestCount(for: WaasWalletAPI.UseWallet.urlPath) == 0)
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
        for: WaasWalletAPI.CommitVerifier.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = await fixture.client.handleOidcRedirectCallback(
        "otherapp://auth/callback?code=auth-code&state=\(started.state)"
    )

    guard case .notOidcRedirectCallback = result else {
        #expect(Bool(false))
        return
    }
    #expect(fixture.client.canResumeOidcRedirectAuth)
    #expect(fixture.oidcRedirectAuthStore.pending?.verifier == "oidc-verifier-123")
    #expect(fixture.transport.requestCount(for: WaasWalletAPI.CompleteAuth.urlPath) == 0)
}

@Test func TestWalletHandleOidcRedirectCallbackReturnsFailedAndClearsPendingAuthForProviderError() async throws {
    let fixture = makeMockWalletClient(oidcNonceGenerator: { "nonce-123" })
    try fixture.transport.enqueue(
        CommitVerifierResponse(
            verifier: "oidc-verifier-123",
            loginHint: "user@example.com",
            challenge: "pkce-challenge"
        ),
        for: WaasWalletAPI.CommitVerifier.urlPath
    )
    let started = try await fixture.client.startOidcRedirectAuth(
        provider: OidcProviderConfig(
            issuer: "https://issuer.example",
            clientId: "client-123",
            authorizationUrl: "https://issuer.example/oauth/authorize"
        ),
        redirectUri: "omssdkdemo://auth/callback"
    )

    let result = await fixture.client.handleOidcRedirectCallback(
        "omssdkdemo://auth/callback?error=access_denied&error_description=User%20cancelled&state=\(started.state)"
    )

    guard case .failed(let error as OidcRedirectAuthError) = result else {
        #expect(Bool(false))
        return
    }
    #expect(error == .providerError("User cancelled"))
    #expect(fixture.client.walletId == "")
    #expect(fixture.client.walletAddress == "")
    #expect(fixture.client.canResumeOidcRedirectAuth == false)
    #expect(fixture.oidcRedirectAuthStore.pending == nil)
}

private let testCredential = CredentialInfo(
    credentialId: "0xcredential",
    expiresAt: "2026-01-01T00:00:00Z",
    isCaller: true
)

private struct MockWalletClientFixture {
    let client: WalletClient
    let transport: MockWaasTransport
    let signer: MockCredentialSigner
    let keychain: InMemoryKeychain
    let environment: OMSClientEnvironment
    let oidcRedirectAuthStore: InMemoryOidcRedirectAuthStore

    func storedCredentials() throws -> StorableCredentials? {
        guard let json = try keychain.string(forKey: Constants.credentialsStorageKey(environment: environment)) else {
            return nil
        }
        return try StorableCredentials.from(jsonString: json)
    }
}

private func makeMockWalletClient(
    oidcNonceGenerator: @escaping () throws -> String = OidcRedirectAuth.generateNonce
) -> MockWalletClientFixture {
    let environment = OMSClientEnvironment(
        walletApiUrl: "https://wallet.example.test",
        scope: UUID().uuidString
    )
    let transport = MockWaasTransport()
    let keychain = InMemoryKeychain()
    let signer = MockCredentialSigner()
    let oidcRedirectAuthStore = InMemoryOidcRedirectAuthStore()
    let credentialSession = WalletCredentialSession(
        environment: environment,
        keychain: keychain,
        signerFactory: { _, _ in signer }
    )
    let signedClient = WaasWalletClient(
        baseURL: environment.walletApiUrl,
        transport: transport
    )
    let publicClient = WaasWalletPublicClient(
        baseURL: environment.walletApiUrl,
        transport: transport
    )
    let client = WalletClient(
        projectAccessKey: "test-access-key",
        environment: environment,
        credentialSession: credentialSession,
        signedClient: signedClient,
        publicClient: publicClient,
        oidcRedirectAuthStore: oidcRedirectAuthStore,
        oidcNonceGenerator: oidcNonceGenerator
    )
    client.verifier = "verifier"
    client.challenge = "challenge"

    return MockWalletClientFixture(
        client: client,
        transport: transport,
        signer: signer,
        keychain: keychain,
        environment: environment,
        oidcRedirectAuthStore: oidcRedirectAuthStore
    )
}

private func completeAuthResponse(
    identity: Identity = Identity(type: .email, sub: "user@example.com"),
    wallets: [Wallet],
    page: Page? = nil
) -> CompleteAuthResponse {
    CompleteAuthResponse(
        identity: identity,
        wallets: wallets,
        page: page,
        email: "user@example.com",
        credential: testCredential
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
    let headers: [String: String]
}

private enum MockWaasResponse: Sendable {
    case success(Data)
    case httpError(statusCode: Int, body: Data)
    case failure(WebRPCTransportError)
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

    func enqueueFailure(_ error: WebRPCTransportError, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[path, default: []].append(.failure(error))
    }

    func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let response = try recordAndDequeue(
            path: path,
            body: body,
            headers: headers
        )

        switch response {
        case .success(let body):
            return WebRPCHTTPResponse(statusCode: 200, body: body)
        case .httpError(let statusCode, let body):
            return WebRPCHTTPResponse(statusCode: statusCode, body: body)
        case .failure(let error):
            throw error
        }
    }

    private func recordAndDequeue(
        path: String,
        body: Data,
        headers: [String: String]
    ) throws -> MockWaasResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(
            RecordedWebRPCRequest(
                path: path,
                body: body,
                headers: headers
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
