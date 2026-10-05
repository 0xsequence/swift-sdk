import Foundation

struct ParsedPublishableKey: Equatable, Sendable {
    let projectId: String
    let walletApiUrl: String
    let indexerGatewayUrl: String
    let solanaIndexerGatewayUrl: String
    let walletImportTrustedPcr0s: Set<String>

    func environment() -> OMSWalletEnvironment {
        OMSWalletEnvironment(
            walletApiUrl: walletApiUrl,
            indexerGatewayUrl: indexerGatewayUrl,
            solanaIndexerGatewayUrl: solanaIndexerGatewayUrl
        )
    }
}

private struct PublishableKeyRoute {
    let prefix: String
    let apiUrl: String
    let walletImportTrustedPcr0s: Set<String>
}

// Measurements are pinned to the deployed WaaS builds. Production measurements are published in
// WaaS GitHub releases; Staging can advance between releases. During rotation, publish an SDK that
// trusts both measurements before deploying the replacement, then remove the retired measurement.
private let debugWalletImportPcr0s = Set([String(repeating: "0", count: 96)])
private let stagingWalletImportPcr0s: Set<String> = [
    "3d21c70519a0ea3d5e6af43c5323234d90755d1ca08431064bd9687ddde4a4788a0a4736701513eee6008f1ec17e0d23"
]
private let productionWalletImportPcr0s: Set<String> = [
    "1935cbc713f0b43060315689e87285f6ba76bcf06f26d0719735e8d674b71e0eff71dcf77fe90ab32870ef3c954973b7",
    "66d0d20073ec8549b6eb1cd3cd53311495225ec79d68f168ab734b24a69a8ed0f890f85ff31d5f0a79486a4e3a303b3c"
]

private let publishableKeyRoutes = [
    PublishableKeyRoute(
        prefix: "pk_dev_sdbx_",
        apiUrl: "https://sandbox-api.dev.polygon-dev.technology",
        walletImportTrustedPcr0s: debugWalletImportPcr0s
    ),
    PublishableKeyRoute(
        prefix: "pk_dev_live_",
        apiUrl: "https://api.dev.polygon-dev.technology",
        walletImportTrustedPcr0s: debugWalletImportPcr0s
    ),
    PublishableKeyRoute(
        prefix: "pk_stg_sdbx_",
        apiUrl: "https://sandbox-api.stg.polygon-dev.technology",
        walletImportTrustedPcr0s: stagingWalletImportPcr0s
    ),
    PublishableKeyRoute(
        prefix: "pk_stg_live_",
        apiUrl: "https://api.stg.polygon-dev.technology",
        walletImportTrustedPcr0s: stagingWalletImportPcr0s
    ),
    PublishableKeyRoute(
        prefix: "pk_sdbx_",
        apiUrl: "https://sandbox-api.polygon.technology",
        walletImportTrustedPcr0s: productionWalletImportPcr0s
    ),
    PublishableKeyRoute(
        prefix: "pk_live_",
        apiUrl: "https://api.polygon.technology",
        walletImportTrustedPcr0s: productionWalletImportPcr0s
    )
]

func parsePublishableKey(_ publishableKey: String) throws -> ParsedPublishableKey {
    guard let route = publishableKeyRoutes.first(where: { publishableKey.hasPrefix($0.prefix) }) else {
        throw invalidPublishableKey()
    }

    let suffix = String(publishableKey.dropFirst(route.prefix.count))
    let keyParts = suffix.split(separator: "_", omittingEmptySubsequences: false)
    guard keyParts.count == 2,
          keyParts.allSatisfy({ !$0.isEmpty }) else {
        throw invalidPublishableKey()
    }

    return ParsedPublishableKey(
        projectId: "prj_\(keyParts[0])",
        walletApiUrl: route.apiUrl,
        indexerGatewayUrl: "\(route.apiUrl)/v1/IndexerGateway/",
        solanaIndexerGatewayUrl: "\(route.apiUrl)/v1/SolanaIndexerGateway/",
        walletImportTrustedPcr0s: route.walletImportTrustedPcr0s
    )
}

private func invalidPublishableKey() -> OMSWalletError {
    OMSWalletError(
        code: .validationError,
        message: "Invalid publishableKey."
    )
}
