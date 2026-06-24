import Foundation
import Testing
@testable import OMS_SDK

@Test func TestSupportedNetworks() throws {
    let oms = try OMSClient(publishableKey: "pk_dev_sdbx_project_key")
    
    #expect(Network.supportedNetworks == [
        .mainnet,
        .sepolia,
        .polygon,
        .polygonAmoy,
        .arbitrum,
        .arbitrumSepolia,
        .optimism,
        .optimismSepolia,
        .base,
        .baseSepolia,
        .bsc,
        .bscTestnet,
        .arbitrumNova,
        .avalanche,
        .avalancheTestnet,
        .katana,
    ])

    #expect(oms.findNetworkById(chainId: 8453) == .base)
    #expect(oms.findNetworkById(chainId: 747474) == .katana)
    #expect(oms.findNetworkByName(name: "optimism-sepolia") == .optimismSepolia)
    #expect(Network(rawValue: "arbitrum-sepolia") == .arbitrumSepolia)
    #expect(Network(rawValue: "amoy") == .polygonAmoy)

    #expect(Network.polygon.displayName == "Polygon")
    #expect(Network.polygon.description == "Polygon")
    #expect(Network.polygon.id == 137)
    #expect(Network.polygon.name == "polygon")
    #expect(Network.polygon.nativeTokenSymbol == "POL")
    #expect(Network.polygon.explorerUrl == "https://polygonscan.com")
    #expect(Network.polygonAmoy.name == "amoy")
    #expect(Network.amoy == .polygonAmoy)
}

@Test func TestDefaultEnvironmentUsesSandboxGateway() throws {
    let environment = OMSClientEnvironment(
        indexerGatewayUrl: "https://gateway.example.test/v1/IndexerGateway/"
    )

    #expect(OMSClientEnvironment.defaultWalletApiUrl == "https://sandbox-api.dev.polygon-dev.technology")
    #expect(OMSClientEnvironment.defaultIndexerGatewayUrl == "https://sandbox-api.dev.polygon-dev.technology/v1/IndexerGateway/")
    #expect(environment.indexerGatewayUrl == "https://gateway.example.test/v1/IndexerGateway/")
    #expect(environment.walletOrigin == nil)
}

@Test func TestPublishableKeyRoutingDerivesProjectAndApiUrls() throws {
    let routes = [
        ("pk_dev_sdbx_project_key", "https://sandbox-api.dev.polygon-dev.technology"),
        ("pk_dev_live_project_key", "https://api.dev.polygon-dev.technology"),
        ("pk_stg_sdbx_project_key", "https://sandbox-api.stg.polygon-dev.technology"),
        ("pk_stg_live_project_key", "https://api.stg.polygon-dev.technology"),
        ("pk_sdbx_project_key", "https://sandbox-api.polygon.technology"),
        ("pk_live_project_key", "https://api.polygon.technology")
    ]

    for (publishableKey, apiUrl) in routes {
        let parsedKey = try parsePublishableKey(publishableKey)
        #expect(parsedKey.projectId == "prj_project")
        #expect(parsedKey.walletApiUrl == apiUrl)
        #expect(parsedKey.indexerGatewayUrl == "\(apiUrl)/v1/IndexerGateway/")

        let oms = try OMSClient(publishableKey: publishableKey)
        #expect(oms.wallet.projectId == "prj_project")
        #expect(oms.wallet.environment.walletApiUrl == apiUrl)
        #expect(oms.wallet.environment.indexerGatewayUrl == "\(apiUrl)/v1/IndexerGateway/")
    }
}

@Test func TestPublishableKeyRoutingRejectsInvalidKeys() throws {
    for publishableKey in [
        "pk_test_sdbx_project_key",
        "pk_dev_sdbx_project",
        "pk_dev_sdbx__key",
        "pk_dev_sdbx_project_"
    ] {
        do {
            _ = try OMSClient(publishableKey: publishableKey)
            #expect(Bool(false), "Expected invalid publishable key")
        } catch let error as OmsSdkError {
            #expect(error.code == .validationError)
            #expect(error.operation == nil)
            #expect(error.localizedDescription == "Invalid publishableKey.")
        } catch {
            #expect(Bool(false), "Expected OmsSdkError")
        }
    }
}

@Test func TestSignedWaasTransportIncludesConfiguredOrigin() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(#"{"verifier":"test@example.com","loginHint":"","challenge":"challenge"}"#.utf8)
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]

    let host = RecordingURLProtocol.register(recorder: recorder)
    let session = URLSession(configuration: configuration)
    let transport = SignedWaasTransport(
        publishableKey: "test-key",
        scope: "proj_1",
        signer: TestCredentialSigner(),
        origin: "https://0xsequence.github.io",
        session: session
    )
    let client = WaasClient(
        baseURL: "https://\(host)",
        transport: transport
    )

    _ = try await client.commitVerifier(
        CommitVerifierRequest(
            identityType: .email,
            authMode: .otp,
            metadata: [:],
            handle: "test@example.com"
        )
    )

    let request = try #require(recorder.recordedRequest())
    #expect(request.url?.path == "/v1/Waas/CommitVerifier")
    #expect(request.value(forHTTPHeaderField: "Api-Key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Origin") == "https://0xsequence.github.io")
    #expect(request.value(forHTTPHeaderField: "Webrpc")?.contains("waas@v1-26.6.17-061733f") == true)
    #expect(request.value(forHTTPHeaderField: "OMS-Wallet-Signature")?.contains("scope=\"proj_1\"") == true)
}

@Test func TestIndexerCancelledRequestPreservesCancellation() async throws {
    let recorder = IndexerRequestRecorder(transportError: URLError(.cancelled))
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getBalances(
            GetBalancesParams(
                walletAddress: "0xwallet",
                networks: [.polygon],
                includeMetadata: false
            )
        )
        #expect(Bool(false), "Expected cancellation")
    } catch is CancellationError {
    } catch {
        #expect(Bool(false), "Expected CancellationError, got \(error)")
    }
}

@Test func TestGetBalancesEncodesGatewayScopeFiltersAndHeaders() async throws {
    let recorder = IndexerRequestRecorder()
    let client = makeRecordingIndexerClient(recorder: recorder)

    _ = try await client.getBalances(
        GetBalancesParams(
            walletAddress: "0xwallet",
            networks: [.polygon, .base],
            contractAddresses: ["0xTokenContract"],
            includeMetadata: false,
            omitPrices: true,
            tokenIds: ["123"],
            contractStatus: .verified,
            page: TokenBalancesPageRequest(page: 2, pageSize: 100)
        )
    )

    let request = try #require(recorder.recordedRequest())
    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let filter = try #require(payload["filter"] as? [String: Any])
    let page = try #require(payload["page"] as? [String: Any])

    #expect(request.url?.path == "/v1/IndexerGateway/GetTokenBalancesDetails")
    #expect(request.value(forHTTPHeaderField: "Api-Key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Webrpc")?.contains("sequence-indexer@v0.4.0") == true)
    #expect(request.value(forHTTPHeaderField: "Origin") == nil)
    #expect(payload["chainIds"] as? [Int] == [137, 8453])
    #expect(payload["networkType"] == nil)
    #expect(payload["omitMetadata"] as? Bool == true)
    #expect(filter["accountAddresses"] as? [String] == ["0xwallet"])
    #expect(filter["contractWhitelist"] as? [String] == ["0xTokenContract"])
    #expect(filter["contractStatus"] as? String == "VERIFIED")
    #expect(filter["omitNativeBalances"] as? Bool == false)
    #expect(filter["omitPrices"] as? Bool == true)
    #expect(filter["tokenIDs"] as? [String] == ["123"])
    #expect(page["page"] as? Int == 2)
    #expect(page["pageSize"] as? Int == 100)
}

@Test func TestGetTransactionHistoryEncodesGatewayFiltersAndDecodesTransactions() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"""
            {
              "page": {"page": 0, "pageSize": 40, "more": false},
              "transactions": [
                {
                  "chainId": 80002,
                  "results": [
                    {
                      "txnHash": "0xtxn",
                      "blockNumber": 123,
                      "blockHash": "0xblock",
                      "chainId": 80002,
                      "metaTxnID": "meta-1",
                      "timestamp": "2026-01-01T00:00:00Z",
                      "transfers": [
                        {
                          "transferType": "SEND",
                          "contractAddress": "0xcontract",
                          "tokenIDs": ["7"],
                          "amounts": ["1"],
                          "tokenMetadata": {
                            "7": {
                              "chainId": 80002,
                              "contractAddress": "0xcontract",
                              "tokenID": "7",
                              "name": "Token 7"
                            }
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    let result = try await client.getTransactionHistory(
        GetTransactionHistoryParams(
            walletAddress: "0xwallet",
            networkType: .all,
            contractAddresses: ["0xcontract"],
            transactionHashes: ["0xtxn"],
            metaTransactionIds: ["meta-1"],
            fromBlock: 1,
            toBlock: 200,
            tokenId: "7",
            includeMetadata: true,
            omitPrices: true
        )
    )

    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let filter = try #require(payload["filter"] as? [String: Any])
    let transaction = try #require(result.transactions.first)
    let transfer = try #require(transaction.transfers?.first)

    #expect(recorder.recordedRequest()?.url?.path == "/v1/IndexerGateway/GetTransactionHistory")
    #expect(payload["networkType"] as? String == "ALL")
    #expect(payload["chainIds"] == nil)
    #expect(payload["includeMetadata"] as? Bool == true)
    #expect(filter["accountAddresses"] as? [String] == ["0xwallet"])
    #expect(filter["contractAddresses"] as? [String] == ["0xcontract"])
    #expect(filter["transactionHashes"] as? [String] == ["0xtxn"])
    #expect(filter["metaTransactionIDs"] as? [String] == ["meta-1"])
    #expect(filter["fromBlock"] as? Int == 1)
    #expect(filter["toBlock"] as? Int == 200)
    #expect(filter["tokenID"] as? String == "7")
    #expect(filter["omitPrices"] as? Bool == true)
    #expect(transaction.metaTxnId == "meta-1")
    #expect(transfer.tokenIds == ["7"])
    #expect(transfer.tokenMetadata?["7"]?.tokenId == "7")
}

@Test func TestTokenBalanceDecodesIndexerMetadataFields() throws {
    let fixture = Data(
        #"""
        {
          "contractType": "ERC721",
          "contractAddress": "0xcontract",
          "accountAddress": "0xwallet",
          "tokenID": "123",
          "balance": "1",
          "balanceUSD": "12.34",
          "priceUSD": "12.34",
          "priceUpdatedAt": "2026-01-01T00:00:00Z",
          "blockHash": "0xhash",
          "blockNumber": 12345,
          "chainId": 137,
          "uniqueCollectibles": "1",
          "isSummary": false,
          "contractInfo": {
            "chainId": 137,
            "address": "0xcontract",
            "source": "metadata",
            "name": "Example Token",
            "type": "ERC721",
            "symbol": "EXM",
            "decimals": 0,
            "logoURI": "https://example.com/logo.png",
            "deployed": true,
            "bytecodeHash": "0xbytecode",
            "extensions": {"verified": true},
            "updatedAt": "2026-01-02T00:00:00Z",
            "queuedAt": null,
            "status": "available"
          },
          "tokenMetadata": {
            "chainId": 137,
            "contractAddress": "0xcontract",
            "tokenId": "123",
            "source": "metadata",
            "name": "Example NFT",
            "description": "Example description",
            "image": "ipfs://image",
            "video": "ipfs://video",
            "audio": "ipfs://audio",
            "properties": {"rarity": "rare"},
            "attributes": [{"trait_type": "Level", "value": 7}],
            "image_data": "<svg></svg>",
            "external_url": "https://example.com/token/123",
            "background_color": "ffffff",
            "animation_url": "ipfs://animation",
            "decimals": 0,
            "updatedAt": "2026-01-03T00:00:00Z",
            "assets": [
              {
                "id": 1,
                "collectionId": 2,
                "tokenID": "asset-token",
                "url": "https://example.com/asset.png",
                "metadataField": "image",
                "name": "Asset",
                "filesize": 123456,
                "mimeType": "image/png",
                "width": 640,
                "height": 480,
                "updatedAt": "2026-01-04T00:00:00Z"
              }
            ],
            "status": "available",
            "queuedAt": null,
            "lastFetched": "2026-01-05T00:00:00Z"
          }
        }
        """#.utf8
    )

    let balance = try JSONDecoder().decode(TokenBalance.self, from: fixture)
    let contractInfo = try #require(balance.contractInfo)
    let tokenMetadata = try #require(balance.tokenMetadata)
    let asset = try #require(tokenMetadata.assets?.first)

    #expect(balance.tokenId == "123")
    #expect(balance.balanceUSD == "12.34")
    #expect(balance.priceUSD == "12.34")
    #expect(balance.priceUpdatedAt == "2026-01-01T00:00:00Z")
    #expect(balance.uniqueCollectibles == "1")
    #expect(balance.isSummary == false)
    #expect(contractInfo.symbol == "EXM")
    #expect(contractInfo.decimals == 0)
    #expect(contractInfo.logoURI == "https://example.com/logo.png")
    #expect(tokenMetadata.tokenId == "123")
    #expect(tokenMetadata.name == "Example NFT")
    #expect(tokenMetadata.imageData == "<svg></svg>")
    #expect(tokenMetadata.externalUrl == "https://example.com/token/123")
    #expect(asset.tokenId == "asset-token")
    #expect(asset.url == "https://example.com/asset.png")

    if case .bool(true)? = contractInfo.extensions?["verified"] {
    } else {
        #expect(Bool(false), "Expected contractInfo.extensions.verified to decode")
    }

    if case .string("rare")? = tokenMetadata.properties?["rarity"] {
    } else {
        #expect(Bool(false), "Expected tokenMetadata.properties.rarity to decode")
    }
}

@Test func TestIndexerNonSuccessResponsesThrowOmsHttpError() async throws {
    let tokenBalancesRecorder = IndexerRequestRecorder(
        statusCode: 500,
        responseBody: Data(#"{"msg":"gateway unavailable"}"#.utf8)
    )
    let tokenBalancesClient = makeRecordingIndexerClient(recorder: tokenBalancesRecorder)

    do {
        _ = try await tokenBalancesClient.getBalances(
            GetBalancesParams(
                walletAddress: "0xwallet",
                networks: [.polygon],
                includeMetadata: true
            )
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetBalances)
        #expect(error.status == 500)
        #expect(error.retryable == true)
        #expect(error.localizedDescription == "gateway unavailable")
    } catch {
        #expect(Bool(false), "Expected OmsSdkError")
    }

    let historyRecorder = IndexerRequestRecorder(
        statusCode: 404,
        responseBody: Data(#"{"cause":"not found"}"#.utf8)
    )
    let historyClient = makeRecordingIndexerClient(recorder: historyRecorder)

    do {
        _ = try await historyClient.getTransactionHistory(
            GetTransactionHistoryParams(
                walletAddress: "0xwallet",
                networks: [.polygon]
            )
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetTransactionHistory)
        #expect(error.status == 404)
        #expect(error.retryable == false)
        #expect(error.localizedDescription == "not found")
    } catch {
        #expect(Bool(false), "Expected OmsSdkError")
    }
}

@available(macOS 12.0, iOS 15.0, *)
private func makeRecordingIndexerClient(recorder: IndexerRequestRecorder) -> IndexerClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1

    let host = RecordingURLProtocol.register(recorder: recorder)

    let session = URLSession(configuration: configuration)
    let httpClient = HttpClient(session: session)
    let environment = OMSClientEnvironment(
        indexerGatewayUrl: "https://\(host)/v1/IndexerGateway/"
    )

    return IndexerClient(
        publishableKey: "test-key",
        environment: environment,
        client: httpClient
    )
}

private final class IndexerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    let statusCode: Int
    let responseBody: Data
    let transportError: (any Error)?
    private var body: Data?
    private var request: URLRequest?

    init(
        statusCode: Int = 200,
        responseBody: Data = Data(#"{"page":{"page":0,"pageSize":40,"more":false},"nativeBalances":[],"balances":[]}"#.utf8),
        transportError: (any Error)? = nil
    ) {
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.transportError = transportError
    }

    func record(request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
        self.body = body
    }

    func recordedBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    func recordedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordersByHost: [String: IndexerRequestRecorder] = [:]

    static func register(recorder: IndexerRequestRecorder) -> String {
        let host = "indexer-\(UUID().uuidString).test"
        lock.lock()
        defer { lock.unlock() }
        recordersByHost[host] = recorder
        return host
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let recorder = Self.recorder(for: request)
        recorder?.record(request: request, body: Self.bodyData(for: request))

        if let error = recorder?.transportError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: recorder?.statusCode ?? 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = recorder?.responseBody ?? Data()

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func recorder(for request: URLRequest) -> IndexerRequestRecorder? {
        guard let host = request.url?.host else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let recorder = recordersByHost[host] {
            return recorder
        }
        return recordersByHost.first { host.hasSuffix("-\($0.key)") }?.value
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}

@available(macOS 12.0, iOS 15.0, *)
private struct TestCredentialSigner: CredentialSigner {
    let alg: SigningAlgorithm = .ecdsaP256Sha256

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
        true
    }

    func clear() throws {}
}
