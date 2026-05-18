import Foundation
import CryptoKit
import Testing
@testable import OMS_SDK

let privateKey: [UInt8] = [
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11
]

@Test func TestKeccak256() async throws {
    let input    = "challenge123456"
    let expected = "0x752c0acc530a06ddbccae9295f7fd287037f7e2c19272c7506adce3175075fdd"

    let result = Keccak256.Keccak256(data: input)

    #expect(result == expected)
}

@Test func TestEmailAuthChallenge() async throws {
    let challenge  = "challenge"
    let code = "123456"
    let expected = "2oXiHHjzvN3XzdxGxWTK_c9hZf7pom0OovssPvI7q3M"
    
    let answer = RequestUtils.hashEmailAuthAnswer(
        challenge: challenge,
        code: code
    )

    #expect(answer == expected)
}

@Test func TestWalletRequestPreimageIncludesScope() async throws {
    let payload = "{\"verifier\":\"email@example.com\"}"
    let expected = """
    POST /rpc/Wallet/CommitVerifier
    nonce: 1234567890
    scope: proj_1

    {"verifier":"email@example.com"}
    """

    let preimage = RequestUtils.buildWalletRequestPreimage(
        endpoint: "/CommitVerifier",
        nonce: "1234567890",
        scope: OMSClientEnvironment.defaultScope,
        payload: payload
    )

    #expect(preimage == expected)
}

@Test func TestWalletSignatureHeaderUsesSigningAlgorithm() async throws {
    let credential = "0x04" + String(repeating: "11", count: 64)
    let signature = "0x" + String(repeating: "22", count: 64)
    let header = RequestUtils.buildWalletSignatureHeader(
        alg: .ecdsaP256Sha256,
        scope: "proj_1",
        cred: credential,
        nonce: "1234567890",
        sig: signature
    )
    let expected = "alg=\"ecdsa-p256-sha256\", scope=\"proj_1\", cred=\"\(credential)\", nonce=1234567890, sig=\"\(signature)\""
 
    #expect(header == expected)
}

@Test func TestP256RawSignatureDerRoundTrip() throws {
    let rawSignature = Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x80)]
        + Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x01)]

    let derSignature = try P256EcdsaSignatureEncoding.rawToDer(rawSignature)
    let decoded = try P256EcdsaSignatureEncoding.derToRaw(derSignature)

    #expect(decoded == rawSignature)
}

@Test func TestGetTokenBalances() async throws {
    let oms = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )
    
    let contractAddress = "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359"
    let walletAddress = "0x8e3E38fe7367dd3b52D1e281E4e8400447C8d8B9"
    
    let result = try await oms.indexer.getTokenBalances(
        network: Network.polygon,
        contractAddress: contractAddress,
        walletAddress: walletAddress,
        includeMetadata: true
    )
    
    for r in result.balances {
        print("Account Address: \(r.accountAddress ?? "undefined"), Balance: \(r.balance ?? "undefined")")
        #expect(r.chainId == 137)
        #expect(r.contractAddress == contractAddress.lowercased())
        #expect(r.accountAddress == walletAddress.lowercased())
    }
}

@Test func TestGetNativeTokenBalance() async throws {
    let oms = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )
    
    let walletAddress = "0x8e3E38fe7367dd3b52D1e281E4e8400447C8d8B9"
    
    let balance = try await oms.indexer.getNativeTokenBalance(
        network: .polygon,
        walletAddress: walletAddress
    )
    
    print("Account Address: \(balance?.accountAddress ?? "undefined"), Balance: \(balance?.balance ?? "undefined")")

    #expect(balance?.chainId == 137)
    #expect(balance?.accountAddress == walletAddress.lowercased())
}

@Test func TestParseUnits() throws {
    #expect(try parseUnits(value: "1", decimals: 18) == "1000000000000000000")
    #expect(try parseUnits(value: "1.23", decimals: 6) == "1230000")
    #expect(try parseUnits(value: ".5", decimals: 6) == "500000")
    #expect(try parseUnits(value: "1.2300", decimals: 2) == "123")
    #expect(try parseUnits(value: "0.000000000000000001", decimals: 18) == "1")
}

@Test func TestSupportedNetworks() throws {
    #expect(Network.supportedNetworks == [.polygon, .polygonAmoy])

    #expect(Network.from(chainId: "137") == .polygon)
    #expect(Network.from(chainId: "80002") == .polygonAmoy)
    #expect(Network.from(chainId: "1") == nil)

    #expect(Network.polygon.displayName == "Polygon")
    #expect(Network.polygon.description == "Polygon")
}

@Test func TestIndexerURLUsesNetworkIndexerName() throws {
    let environment = OMSClientEnvironment(
        indexerURLTemplate: "https://{value}-indexer.sequence.app/rpc/Indexer/"
    )

    #expect(environment.indexerURLTemplate == "https://{value}-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygon)?.absoluteString == "https://polygon-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygonAmoy)?.absoluteString == "https://amoy-indexer.sequence.app/rpc/Indexer/")
}

@Test func TestFormatUnits() throws {
    #expect(try formatUnits(value: "1000000000000000000", decimals: 18) == "1")
    #expect(try formatUnits(value: "1230000", decimals: 6) == "1.23")
    #expect(try formatUnits(value: "1", decimals: 6) == "0.000001")
    #expect(try formatUnits(value: "1200000", decimals: 6) == "1.2")
    #expect(try formatUnits(value: "1", decimals: 18) == "0.000000000000000001")
}

@Test func TestParseUnitsRejectsTooManyDecimals() {
    do {
        _ = try parseUnits(value: "1.234", decimals: 2)
        #expect(Bool(false))
    } catch UnitConversionError.fractionalComponentExceedsDecimals(let value, let decimals) {
        #expect(value == "1.234")
        #expect(decimals == 2)
    } catch {
        #expect(Bool(false))
    }
}

@Test func TestCheapestFeeOptionUsesNumericValue() async throws {
    let token = FeeToken(
        network: "polygon",
        name: "USDC",
        symbol: "USDC",
        type: "erc20",
        logoUrl: "",
        tokenId: "usdc"
    )
    let options = [
        FeeOption(token: token, value: "100", displayValue: "100"),
        FeeOption(token: token, value: "20", displayValue: "20")
    ]

    let selected = try await FeeOptionSelector.cheapest(options)

    #expect(selected.value == "20")
}

@Test func TestSessionStateParsesExpiresAt() throws {
    let state = SessionState(
        walletAddress: "0xabc",
        expiresAtString: "2026-01-01T00:00:00Z",
        loginType: .email,
        sessionEmail: "user@example.com"
    )

    #expect(state.walletAddress == "0xabc")
    #expect(state.expiresAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(state.loginType == .email)
    #expect(state.sessionEmail == "user@example.com")
}

@Test func TestStorableCredentialsRoundTripSessionMetadata() throws {
    let credentials = StorableCredentials(
        walletId: "wallet-1",
        walletAddress: "0xabc",
        signerCredentialId: "0xsigner",
        alg: .ecdsaP256Sha256,
        expiresAt: "2026-01-01T00:00:00Z",
        loginType: .email,
        sessionEmail: "user@example.com"
    )

    let restored = try StorableCredentials.from(jsonString: credentials.jsonString())

    #expect(restored.walletId == "wallet-1")
    #expect(restored.walletAddress == "0xabc")
    #expect(restored.signerCredentialId == "0xsigner")
    #expect(restored.alg == .ecdsaP256Sha256)
    #expect(restored.expiresAt == "2026-01-01T00:00:00Z")
    #expect(restored.loginType == .email)
    #expect(restored.sessionEmail == "user@example.com")
}

@Test func TestOMSClientIdentityMapsSessionLoginType() throws {
    let emailIdentity = OMSClientIdentity(Identity(type: .email, sub: "user@example.com"))
    let googleIdentity = OMSClientIdentity(Identity(type: .oidc, iss: "https://accounts.google.com", sub: "google-sub"))
    let oidcIdentity = OMSClientIdentity(Identity(type: .oidc, iss: "https://idp.example.com", sub: "oidc-sub"))
    let phoneIdentity = OMSClientIdentity(Identity(type: .phone, sub: "+15555550100"))

    #expect(emailIdentity.sessionLoginType == .email)
    #expect(googleIdentity.sessionLoginType == .googleAuth)
    #expect(oidcIdentity.sessionLoginType == .oidc)
    #expect(phoneIdentity.sessionLoginType == nil)
}

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

    func storedCredentials() throws -> StorableCredentials? {
        guard let json = try keychain.string(forKey: Constants.credentialsStorageKey(environment: environment)) else {
            return nil
        }
        return try StorableCredentials.from(jsonString: json)
    }
}

private func makeMockWalletClient() -> MockWalletClientFixture {
    let environment = OMSClientEnvironment(
        walletApiUrl: "https://wallet.example.test",
        scope: UUID().uuidString
    )
    let transport = MockWaasTransport()
    let keychain = InMemoryKeychain()
    let signer = MockCredentialSigner()
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
        publicClient: publicClient
    )
    client.verifier = "verifier"
    client.challenge = "challenge"

    return MockWalletClientFixture(
        client: client,
        transport: transport,
        signer: signer,
        keychain: keychain,
        environment: environment
    )
}

private func completeAuthResponse(
    wallets: [Wallet],
    page: Page? = nil
) -> CompleteAuthResponse {
    CompleteAuthResponse(
        identity: Identity(type: .email, sub: "user@example.com"),
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
        "0xmock-credential"
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
        headers: [String : String]
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
