public struct OMSClientEnvironment : Sendable {
    public static let defaultWalletApiUrl: String = "https://d1sctl7y41hot5.cloudfront.net"
    public static let defaultApiRpcUrl: String = "https://dev-api.sequence.app/rpc/API"
    public static let defaultIndexerUrlTemplate: String = "https://dev-{value}-indexer.sequence.app/rpc/Indexer/"
    public static let defaultScope: String = "proj_1"

    public let walletApiUrl: String
    public let apiRpcUrl: String
    public let indexerUrlTemplate: String
    public let scope: String

    public init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerUrlTemplate: String = OMSClientEnvironment.defaultIndexerUrlTemplate,
        scope: String = OMSClientEnvironment.defaultScope
    ) {
        self.walletApiUrl = walletApiUrl
        self.apiRpcUrl = apiRpcUrl
        self.indexerUrlTemplate = indexerUrlTemplate
        self.scope = scope
    }
}
