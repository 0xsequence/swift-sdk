import Foundation

struct OMSWalletEnvironment: Equatable, Sendable {
    let walletApiUrl: String
    let indexerGatewayUrl: String
    let solanaIndexerGatewayUrl: String

    init(
        walletApiUrl: String,
        indexerGatewayUrl: String,
        solanaIndexerGatewayUrl: String? = nil
    ) {
        self.walletApiUrl = walletApiUrl
        self.indexerGatewayUrl = indexerGatewayUrl
        self.solanaIndexerGatewayUrl = solanaIndexerGatewayUrl
            ?? "\(walletApiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/SolanaIndexerGateway/"
    }
}
