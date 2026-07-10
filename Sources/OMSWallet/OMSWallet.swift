@available(macOS 12.0, iOS 15.0, *)
public final class OMSWallet: Sendable {
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

}
