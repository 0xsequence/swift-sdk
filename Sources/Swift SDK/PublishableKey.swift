import Foundation

struct ParsedPublishableKey: Equatable, Sendable {
    let projectId: String
    let walletApiUrl: String
    let indexerGatewayUrl: String

    func environment(walletOrigin: String? = nil) -> OMSClientEnvironment {
        OMSClientEnvironment(
            walletApiUrl: walletApiUrl,
            indexerGatewayUrl: indexerGatewayUrl,
            walletOrigin: walletOrigin
        )
    }
}

private struct PublishableKeyRoute {
    let prefix: String
    let apiUrl: String
}

private let publishableKeyRoutes = [
    PublishableKeyRoute(prefix: "pk_dev_sdbx_", apiUrl: "https://sandbox-api.dev.polygon-dev.technology"),
    PublishableKeyRoute(prefix: "pk_dev_live_", apiUrl: "https://api.dev.polygon-dev.technology"),
    PublishableKeyRoute(prefix: "pk_stg_sdbx_", apiUrl: "https://sandbox-api.stg.polygon-dev.technology"),
    PublishableKeyRoute(prefix: "pk_stg_live_", apiUrl: "https://api.stg.polygon-dev.technology"),
    PublishableKeyRoute(prefix: "pk_sdbx_", apiUrl: "https://sandbox-api.polygon.technology"),
    PublishableKeyRoute(prefix: "pk_live_", apiUrl: "https://api.polygon.technology")
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
        indexerGatewayUrl: "\(route.apiUrl)/v1/IndexerGateway/"
    )
}

private func invalidPublishableKey() -> OmsSdkError {
    OmsSdkError(
        code: .validationError,
        message: "Invalid publishableKey."
    )
}
