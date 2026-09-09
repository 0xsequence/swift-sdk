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

// Staging and Production measurements come from the corresponding WaaS GitHub releases. During
// rotation, publish an SDK that trusts both the current and replacement measurements before the
// replacement enclave is deployed, then remove the retired measurement in a later SDK release.
private let debugWalletImportPcr0s = Set([String(repeating: "0", count: 96)])
private let stagingWalletImportPcr0s: Set<String> = [
    "e4da1f70f6e781d7196dff36d21e57bb5603ec4bcacefb7061493049292b76b620b0ad23b82e280d6130f67384051e9f"
]
private let productionWalletImportPcr0s: Set<String> = [
    "671f22183eed852f4051a50ee54b45153499501538cbd64a277b8ff22a012b37f1905ebfcf7a6be8ce00ec0c8db7bbd2"
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
