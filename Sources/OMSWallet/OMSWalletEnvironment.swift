import Foundation

struct OMSWalletEnvironment: Equatable, Sendable {
    let walletApiUrl: String
    let indexerGatewayUrl: String

    init(
        walletApiUrl: String,
        indexerGatewayUrl: String
    ) {
        self.walletApiUrl = walletApiUrl
        self.indexerGatewayUrl = indexerGatewayUrl
    }
}
