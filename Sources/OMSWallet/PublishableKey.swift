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
    "e271fe4b26c9d58d6089b908ab713f888e6107e2cb4782ddaceea950bbec9971ccd9159e7a099bd506e04ce55c3da696"
]
private let productionWalletImportPcr0s: Set<String> = [
    "1935cbc713f0b43060315689e87285f6ba76bcf06f26d0719735e8d674b71e0eff71dcf77fe90ab32870ef3c954973b7"
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
