import Foundation
import Testing
@testable import OMS_SDK

@Test func TestSupportedNetworks() throws {
    let oms = OMSClient(publishableKey: "test", projectId: "test")
    
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

@Test func TestIndexerURLUsesNetworkIndexerName() throws {
    let environment = OMSClientEnvironment(
        indexerURLTemplate: "https://{value}-indexer.sequence.app/rpc/Indexer/"
    )

    #expect(environment.indexerURLTemplate == "https://{value}-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygon)?.absoluteString == "https://polygon-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygonAmoy)?.absoluteString == "https://amoy-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .arbitrumSepolia)?.absoluteString == "https://arbitrum-sepolia-indexer.sequence.app/rpc/Indexer/")
}

@Test func TestGetTokenBalancesEncodesOptionalContractAddressAndPage() async throws {
    let recorder = IndexerRequestRecorder()
    let client = makeRecordingIndexerClient(recorder: recorder)

    _ = try await client.getTokenBalances(
        network: .polygon,
        walletAddress: "0xwallet",
        includeMetadata: true
    )

    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let page = try #require(payload["page"] as? [String: Any])

    #expect(payload["contractAddress"] == nil)
    #expect(payload["accountAddress"] as? String == "0xwallet")
    #expect(payload["includeMetadata"] as? Bool == true)
    #expect(page["page"] as? Int == 0)
    #expect(page["pageSize"] as? Int == 40)
    #expect(page["more"] as? Bool == false)

    let customPageRecorder = IndexerRequestRecorder()
    let customPageClient = makeRecordingIndexerClient(recorder: customPageRecorder)

    _ = try await customPageClient.getTokenBalances(
        network: .polygon,
        contractAddress: "0xTokenContract",
        walletAddress: "0xwallet",
        includeMetadata: false,
        page: TokenBalancesPageRequest(page: 2, pageSize: 100)
    )

    let customPageBody = try #require(customPageRecorder.recordedBody())
    let customPagePayload = try #require(JSONSerialization.jsonObject(with: customPageBody) as? [String: Any])
    let customPage = try #require(customPagePayload["page"] as? [String: Any])

    #expect(customPagePayload["contractAddress"] as? String == "0xTokenContract")
    #expect(customPagePayload["accountAddress"] as? String == "0xwallet")
    #expect(customPagePayload["includeMetadata"] as? Bool == false)
    #expect(customPage["page"] as? Int == 2)
    #expect(customPage["pageSize"] as? Int == 100)
    #expect(customPage["more"] as? Bool == false)
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
        responseBody: Data(#"{"page":{"page":0,"pageSize":40,"more":false},"balances":[]}"#.utf8)
    )
    let tokenBalancesClient = makeRecordingIndexerClient(recorder: tokenBalancesRecorder)

    do {
        _ = try await tokenBalancesClient.getTokenBalances(
            network: .polygon,
            walletAddress: "0xwallet",
            includeMetadata: true
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetTokenBalances)
        #expect(error.status == 500)
        #expect(error.retryable == true)
    } catch {
        #expect(Bool(false), "Expected OmsSdkError")
    }

    let nativeBalanceRecorder = IndexerRequestRecorder(
        statusCode: 404,
        responseBody: Data(#"{"balance":null}"#.utf8)
    )
    let nativeBalanceClient = makeRecordingIndexerClient(recorder: nativeBalanceRecorder)

    do {
        _ = try await nativeBalanceClient.getNativeTokenBalance(
            network: .polygon,
            walletAddress: "0xwallet"
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OmsSdkError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetNativeTokenBalance)
        #expect(error.status == 404)
        #expect(error.retryable == false)
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
        indexerURLTemplate: "https://{value}-\(host)/rpc/Indexer/"
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
    private var body: Data?

    init(
        statusCode: Int = 200,
        responseBody: Data = Data(#"{"page":{"page":0,"pageSize":40,"more":false},"balances":[]}"#.utf8)
    ) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func record(body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        self.body = body
    }

    func recordedBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
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
        recorder?.record(body: Self.bodyData(for: request))

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
