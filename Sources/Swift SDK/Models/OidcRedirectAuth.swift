import Foundation
import Security

/// OIDC provider configuration for authorization-code PKCE redirect auth.
public struct OidcProviderConfig: Sendable {
    public let issuer: String
    public let clientId: String
    public let authorizationUrl: String
    public let scopes: [String]
    public let relayRedirectUri: String?
    public let authorizeParams: [String: String]

    public init(
        issuer: String,
        clientId: String,
        authorizationUrl: String,
        scopes: [String] = ["openid", "email", "profile"],
        relayRedirectUri: String? = nil,
        authorizeParams: [String: String] = [:]
    ) {
        self.issuer = issuer
        self.clientId = clientId
        self.authorizationUrl = authorizationUrl
        self.scopes = scopes
        self.relayRedirectUri = relayRedirectUri
        self.authorizeParams = authorizeParams
    }
}

/// Built-in OIDC provider configurations.
public enum OidcProviders {
    public static let defaultGoogleClientId = "970987756660-0dh5gubqfiugm452raf7mm39qaq639hn.apps.googleusercontent.com"
    public static let defaultRelayRedirectUri = "https://waas-cf-relay-staging.0xsequence.workers.dev/callback"

    public static func google(
        clientId: String = Self.defaultGoogleClientId,
        relayRedirectUri: String? = Self.defaultRelayRedirectUri,
        scopes: [String] = ["openid", "email", "profile"],
        authorizeParams: [String: String] = [:]
    ) -> OidcProviderConfig {
        OidcProviderConfig(
            issuer: "https://accounts.google.com",
            clientId: clientId,
            authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth",
            scopes: scopes,
            relayRedirectUri: relayRedirectUri,
            authorizeParams: [
                "access_type": "offline",
                "prompt": "consent"
            ].merging(authorizeParams) { _, new in new }
        )
    }
}

/// Result returned after starting an OIDC authorization-code PKCE redirect flow.
///
/// Open `authorizationUrl` in a browser or ASWebAuthenticationSession, then pass
/// the final app callback URL to `handleOidcRedirectCallback`.
public struct StartOidcRedirectAuthResult: Sendable {
    public let authorizationUrl: String
    public let state: String
    public let challenge: String

    public init(authorizationUrl: String, state: String, challenge: String) {
        self.authorizationUrl = authorizationUrl
        self.state = state
        self.challenge = challenge
    }
}

/// Result of handling an incoming OIDC authorization-code redirect callback.
public enum OidcRedirectAuthResult {
    case completed(wallet: Wallet)
    case walletSelection(PendingWalletSelection)
    case notOidcRedirectCallback
    case noPendingAuth
    case failed(Error)
}

public enum OidcRedirectAuthError: Error, Equatable, Sendable {
    case invalidAuthorizationURL(String)
    case randomBytesUnavailable
    case invalidState
    case stateNonceMismatch
    case stateScopeMismatch
    case stateRedirectUriMismatch
    case providerError(String)
    case missingCode
    case signerMismatch
}

extension OidcRedirectAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL(let url):
            return "Invalid OIDC authorization URL: \(url)"
        case .randomBytesUnavailable:
            return "Unable to generate secure OIDC nonce."
        case .invalidState:
            return "OIDC callback state is invalid."
        case .stateNonceMismatch:
            return "OIDC state nonce mismatch."
        case .stateScopeMismatch:
            return "OIDC state scope mismatch."
        case .stateRedirectUriMismatch:
            return "OIDC state redirect URI mismatch."
        case .providerError(let message):
            return message
        case .missingCode:
            return "OIDC callback URL is missing code."
        case .signerMismatch:
            return "OIDC redirect auth signer mismatch."
        }
    }
}

struct PendingOidcRedirectAuth: Codable, Sendable {
    let verifier: String
    let challenge: String
    let nonce: String
    let redirectUri: String
    let issuer: String
    let authorizationScope: String
    let walletType: WalletType
    let signerCredentialId: String
    let signerKeyType: SigningAlgorithm?
}

protocol OidcRedirectAuthStore: Sendable {
    func load() throws -> PendingOidcRedirectAuth?
    func save(_ pending: PendingOidcRedirectAuth) throws
    func clear() throws
}

@available(macOS 12.0, iOS 15.0, *)
final class KeychainOidcRedirectAuthStore: OidcRedirectAuthStore, @unchecked Sendable {
    private let keychain: any KeychainManaging
    private let storageKey: String

    init(
        projectId: String,
        environment: OMSClientEnvironment,
        keychain: any KeychainManaging = KeychainManager()
    ) {
        self.keychain = keychain
        self.storageKey = Constants.oidcRedirectAuthStorageKey(environment: environment, scope: projectId)
    }

    func load() throws -> PendingOidcRedirectAuth? {
        guard let json = try keychain.string(forKey: storageKey) else {
            return nil
        }
        return try PendingOidcRedirectAuth.from(jsonString: json)
    }

    func save(_ pending: PendingOidcRedirectAuth) throws {
        try keychain.set(pending.jsonString(), forKey: storageKey)
    }

    func clear() throws {
        try keychain.delete(forKey: storageKey)
    }
}

struct OidcCallbackParams: Sendable {
    let code: String?
    let state: String?
    let error: String?
    let errorDescription: String?

    var hasOidcResponse: Bool {
        code != nil || state != nil || error != nil || errorDescription != nil
    }
}

private struct OidcStatePayload: Codable {
    let nonce: String
    let scope: String
    let redirectUri: String?

    enum CodingKeys: String, CodingKey {
        case nonce
        case scope
        case redirectUri = "redirect_uri"
    }
}

enum OidcRedirectAuth {
    static func generateNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw OidcRedirectAuthError.randomBytesUnavailable
        }
        return base64UrlEncode(Data(bytes))
    }

    static func encodeState(
        nonce: String,
        scope: String,
        redirectUri: String? = nil
    ) throws -> String {
        let payload = OidcStatePayload(
            nonce: nonce,
            scope: scope,
            redirectUri: redirectUri
        )
        return base64UrlEncode(try WebRPCJSON.makeEncoder().encode(payload))
    }

    static func buildAuthorizationUrl(
        provider: OidcProviderConfig,
        redirectUri: String,
        state: String,
        challenge: String,
        loginHint: String?,
        authorizeParams: [String: String]
    ) throws -> String {
        guard var components = URLComponents(string: provider.authorizationUrl) else {
            throw OidcRedirectAuthError.invalidAuthorizationURL(provider.authorizationUrl)
        }

        var queryItems = components.queryItems ?? []
        func setQueryParameter(_ name: String, _ value: String) {
            queryItems.removeAll { $0.name == name }
            queryItems.append(URLQueryItem(name: name, value: value))
        }

        for (key, value) in authorizeParams {
            setQueryParameter(key, value)
        }
        if let loginHint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines), !loginHint.isEmpty {
            setQueryParameter("login_hint", loginHint)
        }

        setQueryParameter("client_id", provider.clientId)
        setQueryParameter("redirect_uri", redirectUri)
        setQueryParameter("response_type", "code")
        setQueryParameter("scope", provider.scopes.joined(separator: " "))
        setQueryParameter("state", state)
        setQueryParameter("code_challenge", challenge)
        setQueryParameter("code_challenge_method", "S256")

        components.queryItems = queryItems
        guard let url = components.url?.absoluteString else {
            throw OidcRedirectAuthError.invalidAuthorizationURL(provider.authorizationUrl)
        }
        return url
    }

    static func parseCallbackUrl(_ callbackUrl: String) -> OidcCallbackParams {
        let query = callbackUrl
            .substring(after: "?")
            .substring(before: "#")
        let fragment = callbackUrl.substring(after: "#")
        let params = parseQuery(query).merging(parseQuery(fragment)) { queryValue, _ in queryValue }

        return OidcCallbackParams(
            code: params["code"],
            state: params["state"],
            error: params["error"],
            errorDescription: params["error_description"]
        )
    }

    static func validateState(
        _ encodedState: String,
        pending: PendingOidcRedirectAuth
    ) throws {
        let state = try decodeState(encodedState)
        guard state.nonce == pending.nonce else {
            throw OidcRedirectAuthError.stateNonceMismatch
        }
        guard state.scope == pending.authorizationScope else {
            throw OidcRedirectAuthError.stateScopeMismatch
        }
        guard state.redirectUri == nil || state.redirectUri == pending.redirectUri else {
            throw OidcRedirectAuthError.stateRedirectUriMismatch
        }
    }

    static func matchesRedirectUri(callbackUrl: String, redirectUri: String) -> Bool {
        guard let callback = URLComponents(string: callbackUrl),
              let expected = URLComponents(string: redirectUri) else {
            return false
        }

        return callback.scheme?.lowercased() == expected.scheme?.lowercased()
            && sameAuthority(callback, expected)
            && callback.percentEncodedPath == expected.percentEncodedPath
    }

    private static func sameAuthority(
        _ callback: URLComponents,
        _ expected: URLComponents
    ) -> Bool {
        authority(callback)?.lowercased() == authority(expected)?.lowercased()
    }

    private static func authority(_ components: URLComponents) -> String? {
        var value = ""
        if let user = components.percentEncodedUser {
            value += user
            if let password = components.percentEncodedPassword {
                value += ":\(password)"
            }
            value += "@"
        }
        if let host = components.percentEncodedHost {
            value += host
        }
        if let port = components.port {
            value += ":\(port)"
        }
        return value.isEmpty ? nil : value
    }

    private static func decodeState(_ encodedState: String) throws -> OidcStatePayload {
        guard let data = base64UrlDecode(encodedState) else {
            throw OidcRedirectAuthError.invalidState
        }
        do {
            return try WebRPCJSON.makeDecoder().decode(OidcStatePayload.self, from: data)
        } catch {
            throw OidcRedirectAuthError.invalidState
        }
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }

        return query
            .split(separator: "&", omittingEmptySubsequences: true)
            .reduce(into: [String: String]()) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = urlDecode(String(parts[0]))
                let value = parts.count > 1 ? urlDecode(String(parts[1])) : ""
                result[key] = value
            }
    }

    private static func urlDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64)
    }
}

private extension String {
    func substring(after delimiter: Character) -> String {
        guard let index = firstIndex(of: delimiter) else {
            return ""
        }
        return String(self[self.index(after: index)...])
    }

    func substring(before delimiter: Character) -> String {
        guard let index = firstIndex(of: delimiter) else {
            return self
        }
        return String(self[..<index])
    }
}
