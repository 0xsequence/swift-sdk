@available(macOS 12.0, iOS 15.0, *)
public class OMSClient {
    public let wallet: WalletClient
    public let indexer: IndexerClient

    public init(publishableKey: String, projectId: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.wallet = WalletClient(
            publishableKey: publishableKey,
            projectId: projectId,
            environment: environment
        )

        self.indexer = IndexerClient(
            publishableKey: publishableKey,
            environment: environment
        )
    }

    public var supportedNetworks: [Network] {
        Network.supportedNetworks
    }

    public func findNetworkById(chainId: Int) -> Network? {
        supportedNetworks.first { $0.id == chainId }
    }

    public func findNetworkByName(name: String) -> Network? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedNetworks.first { $0.name.lowercased() == normalized }
            ?? (normalized == "polygonamoy" ? .polygonAmoy : nil)
    }
}
