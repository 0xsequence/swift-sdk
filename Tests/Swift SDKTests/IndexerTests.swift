import Foundation
import Testing
@testable import OMS_SDK

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
