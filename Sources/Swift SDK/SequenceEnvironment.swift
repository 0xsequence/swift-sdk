public struct SequenceEnvironment : Sendable {
    let walletApiUrl: String
    let apiRpcUrl: String
    let indexerUrlTemplate: String
    
    public init() {
        self.walletApiUrl = "https://d1sctl7y41hot5.cloudfront.net"
        self.apiRpcUrl = "https://dev-api.sequence.app/rpc/API"
        self.indexerUrlTemplate = "https://dev-{value}-indexer.sequence.app/rpc/Indexer/"
    }
    
    public init(walletApiUrl: String, apiRpcUrl: String, indexerUrlTemplate: String) {
        self.walletApiUrl = walletApiUrl
        self.apiRpcUrl = apiRpcUrl
        self.indexerUrlTemplate = indexerUrlTemplate
    }
}
