import CryptoKit
import Foundation

class Constants {
    public static func credentialsStorageKey(environment: OMSWalletEnvironment, scope: String) -> String {
        "oms-wallet-credentials-\(environmentScopedSuffix(environment: environment, scope: scope))"
    }

    public static func credentialApplicationTag(environment: OMSWalletEnvironment, scope: String) -> String {
        "oms-wallet-credential-\(environmentScopedSuffix(environment: environment, scope: scope))"
    }

    public static func credentialNonceStorageKey(environment: OMSWalletEnvironment, scope: String) -> String {
        "oms-wallet-credential-nonce-\(environmentScopedSuffix(environment: environment, scope: scope))"
    }

    public static func oidcRedirectAuthStorageKey(environment: OMSWalletEnvironment, scope: String) -> String {
        "oms-wallet-oidc-redirect-auth-\(environmentScopedSuffix(environment: environment, scope: scope))"
    }

    private static func environmentScopedSuffix(environment: OMSWalletEnvironment, scope: String) -> String {
        let source = "\(normalizedWalletApiOrigin(environment.walletApiUrl))\u{0}\(scope)"
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
