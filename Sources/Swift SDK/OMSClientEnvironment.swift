import Foundation

public struct OMSClientEnvironment : Equatable, Sendable {
    public static let defaultWalletApiUrl: String = "https://d26giflyqapd29.cloudfront.net"
    public static let defaultApiRpcUrl: String = "https://dev-api.sequence.app/rpc/API"
    public static let defaultIndexerUrlTemplate: String = "https://dev-{value}-indexer.sequence.app/rpc/Indexer/"
    public static let indexerURLTemplateDefault: String = defaultIndexerUrlTemplate
    public static let defaultScope: String = "proj_1"

    public let walletApiUrl: String
    public let apiRpcUrl: String
    public let indexerUrlTemplate: String
    public let scope: String

    public var indexerURLTemplate: String {
        indexerUrlTemplate
    }

    public init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerUrlTemplate: String = OMSClientEnvironment.defaultIndexerUrlTemplate,
        scope: String = OMSClientEnvironment.defaultScope
    ) {
        self.walletApiUrl = walletApiUrl
        self.apiRpcUrl = apiRpcUrl
        self.indexerUrlTemplate = indexerUrlTemplate
        self.scope = scope
    }

    public init(
        walletApiUrl: String = OMSClientEnvironment.defaultWalletApiUrl,
        apiRpcUrl: String = OMSClientEnvironment.defaultApiRpcUrl,
        indexerURLTemplate: String,
        scope: String = OMSClientEnvironment.defaultScope
    ) {
        self.init(
            walletApiUrl: walletApiUrl,
            apiRpcUrl: apiRpcUrl,
            indexerUrlTemplate: indexerURLTemplate,
            scope: scope
        )
    }

    public func indexerURL(for network: Network) -> URL? {
        URL(string: indexerUrlString(for: network))
    }

    internal func indexerUrlString(for network: Network) -> String {
        indexerUrlTemplate.replacingOccurrences(
            of: "{value}",
            with: network.indexerName
        )
    }
}
