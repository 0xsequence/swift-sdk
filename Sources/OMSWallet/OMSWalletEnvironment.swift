import Foundation

public struct OMSWalletEnvironment : Equatable, Sendable {
    public let walletApiUrl: String
    public let indexerGatewayUrl: String

    public init(
        walletApiUrl: String,
        indexerGatewayUrl: String
    ) {
        self.walletApiUrl = walletApiUrl
        self.indexerGatewayUrl = indexerGatewayUrl
    }
}
