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

@available(macOS 12.0, iOS 15.0, *)
private func makeRecordingIndexerClient(recorder: IndexerRequestRecorder) -> IndexerClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1

    RecordingURLProtocol.recorder = recorder

    let session = URLSession(configuration: configuration)
    let httpClient = HttpClient(session: session)
    let environment = OMSClientEnvironment(
        indexerURLTemplate: "https://{value}-indexer.test/rpc/Indexer/"
    )

    return IndexerClient(
        publishableKey: "test-key",
        environment: environment,
        client: httpClient
    )
}

private final class IndexerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var body: Data?

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
    nonisolated(unsafe) static var recorder: IndexerRequestRecorder?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.recorder?.record(body: Self.bodyData(for: request))

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"{"page":{"page":0,"pageSize":40,"more":false},"balances":[]}"#.utf8)

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

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
