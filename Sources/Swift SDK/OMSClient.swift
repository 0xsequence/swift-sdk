@available(macOS 12.0, iOS 15.0, *)
public class OMSClient {
    public let wallet: WalletClient
    public let indexer: IndexerClient

    public init(projectAccessKey: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.wallet = WalletClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )

        self.indexer = IndexerClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )
    }
    
    public var supportedNetworks: [Network] {
        Network.supportedNetworks
    }

    public func network(chainId: String) -> Network? {
        Network.from(chainId: chainId)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public typealias OmsWallet = OMSClient

public typealias OmsEnvironment = OMSClientEnvironment
