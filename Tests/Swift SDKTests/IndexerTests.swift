import Foundation
import Testing
@testable import OMS_SDK

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
