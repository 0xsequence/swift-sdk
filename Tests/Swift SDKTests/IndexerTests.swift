import Foundation
import Testing
@testable import OMS_SDK

@Test func TestSupportedNetworks() throws {
    let oms = OMSClient(projectAccessKey: "test", projectId: "test")
    
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
