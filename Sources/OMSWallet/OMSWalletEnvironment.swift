import Foundation

struct OMSWalletEnvironment: Equatable, Sendable {
    let walletApiUrl: String
    let indexerGatewayUrl: String
    let solanaIndexerGatewayUrl: String
    let tronIndexerGatewayUrl: String

    init(
        walletApiUrl: String,
        indexerGatewayUrl: String,
        solanaIndexerGatewayUrl: String? = nil,
        tronIndexerGatewayUrl: String? = nil
    ) {
        let apiUrl = walletApiUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.walletApiUrl = walletApiUrl
        self.indexerGatewayUrl = indexerGatewayUrl
        self.solanaIndexerGatewayUrl = solanaIndexerGatewayUrl ?? "\(apiUrl)/v1/SolanaIndexerGateway/"
        self.tronIndexerGatewayUrl = tronIndexerGatewayUrl ?? "\(apiUrl)/v1/TronIndexerGateway/"
    }
}
