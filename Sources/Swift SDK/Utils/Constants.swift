import CryptoKit
import Foundation

class Constants {
    public static func credentialsStorageKey(environment: OMSClientEnvironment) -> String {
        "sequence-credentials-\(environmentScopedSuffix(environment))"
    }

    public static func credentialApplicationTag(environment: OMSClientEnvironment) -> String {
        "oms-client-credential-\(environmentScopedSuffix(environment))"
    }

    public static func credentialNonceStorageKey(environment: OMSClientEnvironment) -> String {
        "oms-client-credential-nonce-\(environmentScopedSuffix(environment))"
    }

    public static func oidcRedirectAuthStorageKey(environment: OMSClientEnvironment) -> String {
        "oms-client-oidc-redirect-auth-\(environmentScopedSuffix(environment))"
    }

    private static func environmentScopedSuffix(_ environment: OMSClientEnvironment) -> String {
        let source = "\(normalizedWalletApiOrigin(environment.walletApiUrl))\u{0}\(environment.scope)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedWalletApiOrigin(_ walletApiUrl: String) -> String {
        guard let components = URLComponents(string: walletApiUrl),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return walletApiUrl
        }

        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        normalized.port = components.port
        return normalized.string ?? walletApiUrl
    }
}
