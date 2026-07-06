@available(macOS 12.0, iOS 15.0, *)
public class OMSWallet {
    public let wallet: WalletClient
    public let indexer: IndexerClient

    public convenience init(
        publishableKey: String
    ) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            parsedKey: parsedKey,
            environment: parsedKey.environment()
        )
    }

    init(
        publishableKey: String,
        parsedKey: ParsedPublishableKey,
        environment: OMSWalletEnvironment
    ) {
        self.wallet = WalletClient(
            publishableKey: publishableKey,
            projectId: parsedKey.projectId,
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
