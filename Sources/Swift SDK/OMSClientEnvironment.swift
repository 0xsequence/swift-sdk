import Foundation

public struct OMSClientEnvironment : Equatable, Sendable {
    public static let defaultWalletApiUrl: String = "https://sandbox-api.dev.polygon-dev.technology"
    public static let defaultApiRpcUrl: String = "https://dev-api.sequence.app/rpc/API"
    public static let defaultIndexerGatewayUrl: String = "https://sandbox-api.dev.polygon-dev.technology/v1/IndexerGateway/"

    public let walletApiUrl: String
    public let apiRpcUrl: String
    public let indexerGatewayUrl: String
    public let walletOrigin: String?

    public init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerGatewayUrl: String = OMSClientEnvironment.defaultIndexerGatewayUrl,
        walletOrigin: String? = nil
    ) {
        self.walletApiUrl = walletApiUrl
        self.apiRpcUrl = apiRpcUrl
        self.indexerGatewayUrl = indexerGatewayUrl
        self.walletOrigin = walletOrigin
    }
}
