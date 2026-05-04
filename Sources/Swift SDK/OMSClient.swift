@available(macOS 12.0, iOS 15.0, *)
public class OMSClient {
    public let wallet: WalletClient
    public let indexer: IndexerClient
    public let utils: OMSClientUtils
    
    public init(projectAccessKey: String, scope: String = "proj_1", environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.wallet = WalletClient(
            projectAccessKey: projectAccessKey,
            scope: scope,
            environment: environment
        )
        
        self.indexer = IndexerClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )

        self.utils = OMSClientUtils()
    }
}
