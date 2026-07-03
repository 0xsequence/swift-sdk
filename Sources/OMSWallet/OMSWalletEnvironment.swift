import Foundation

public struct OMSWalletEnvironment : Equatable, Sendable {
    public static let defaultWalletApiUrl: String = "https://sandbox-api.dev.polygon-dev.technology"
    public static let defaultIndexerGatewayUrl: String = "https://sandbox-api.dev.polygon-dev.technology/v1/IndexerGateway/"

    public let walletApiUrl: String
    public let indexerGatewayUrl: String

    public init(
        walletApiUrl: String = OMSWalletEnvironment.defaultWalletApiUrl,
        indexerGatewayUrl: String = OMSWalletEnvironment.defaultIndexerGatewayUrl
    ) {
        self.walletApiUrl = walletApiUrl
        self.indexerGatewayUrl = indexerGatewayUrl
    }
}
