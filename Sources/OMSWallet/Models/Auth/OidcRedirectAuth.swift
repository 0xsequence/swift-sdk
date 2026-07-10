import Foundation
import Security

/// OIDC redirect auth-code mode.
public enum OIDCAuthMode: String, Codable, Equatable, Sendable {
    case authCode = "auth-code"
    case authCodePKCE = "auth-code-pkce"

    var waasAuthMode: AuthMode {
        switch self {
        case .authCode:
            return .authCode
        case .authCodePKCE:
            return .authCodePkce
        }
    }
}

/// A caller-owned OIDC provider configuration for authorization-code redirect auth.
public struct CustomOIDCProviderConfiguration: Sendable {
    public let issuer: String
    public let clientID: String
    public let authorizationURL: String
    public let provider: String?
    public let providerLabel: String?
    public let scopes: [String]
    public let providerRedirectURI: String
    public let authorizeParams: [String: String]
    public let authMode: OIDCAuthMode

    public init(
        issuer: String,
        clientID: String,
        authorizationURL: String,
        providerRedirectURI: String,
        provider: String? = nil,
        providerLabel: String? = nil,
        scopes: [String] = [],
        authorizeParams: [String: String] = [:],
        authMode: OIDCAuthMode = .authCodePKCE
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.authorizationURL = authorizationURL
        self.provider = provider
        self.providerLabel = providerLabel
        self.scopes = scopes
        self.providerRedirectURI = providerRedirectURI
        self.authorizeParams = authorizeParams
        self.authMode = authMode
    }
}

/// A fixed OIDC provider whose OAuth callback is owned by the OMS relay.
public struct OMSRelayOIDCProvider: Equatable, Hashable, Sendable {
    fileprivate enum Kind: Equatable, Hashable, Sendable {
        case google
        case apple
    }

    fileprivate let kind: Kind

    fileprivate init(kind: Kind) {
        self.kind = kind
    }
}

/// SDK-owned OMS relay provider values.
public enum OMSRelayOIDCProviders {
    public static let google = OMSRelayOIDCProvider(kind: .google)
    public static let apple = OMSRelayOIDCProvider(kind: .apple)
}

struct ResolvedOIDCProviderConfiguration: Sendable {
    let issuer: String
    let clientID: String
    let authorizationURL: String
    let provider: String?
    let providerLabel: String?
    let scopes: [String]
    let authorizeParams: [String: String]
    let authMode: OIDCAuthMode
}

extension OMSRelayOIDCProvider {
    var resolvedConfiguration: ResolvedOIDCProviderConfiguration {
        switch kind {
        case .google:
            return ResolvedOIDCProviderConfiguration(
                issuer: "https://accounts.google.com",
                clientID: "913882656162-7l4ofa0ou2hqo90umlkenhdop1f5inba.apps.googleusercontent.com",
                authorizationURL: "https://accounts.google.com/o/oauth2/v2/auth",
                provider: "google",
                providerLabel: "Google",
                scopes: ["openid", "email", "profile"],
                authorizeParams: [
                    "access_type": "offline",
                    "prompt": "consent"
                ],
                authMode: .authCodePKCE
            )
        case .apple:
            return ResolvedOIDCProviderConfiguration(
                issuer: "https://appleid.apple.com",
                clientID: "service.oms.polygon.technology",
                authorizationURL: "https://appleid.apple.com/auth/authorize",
                provider: "apple",
                providerLabel: "Apple",
                scopes: ["openid", "email"],
                authorizeParams: ["response_mode": "form_post"],
                authMode: .authCodePKCE
            )
        }
    }

    var relayPathComponent: String {
        switch kind {
        case .google:
            return "google"
        case .apple:
            return "apple"
        }
    }
}

extension CustomOIDCProviderConfiguration {
    var resolvedConfiguration: ResolvedOIDCProviderConfiguration {
        ResolvedOIDCProviderConfiguration(
            issuer: issuer,
            clientID: clientID,
            authorizationURL: authorizationURL,
            provider: provider,
            providerLabel: providerLabel,
            scopes: scopes,
            authorizeParams: authorizeParams,
            authMode: authMode
        )
    }
}

/// Result returned after starting an OIDC authorization-code redirect flow.
///
/// Open `authorizationURL` in a browser or ASWebAuthenticationSession, then pass
/// the resulting callback URL to `handleOIDCRedirectCallback`.
public struct StartOIDCRedirectAuthResult: Sendable {
    public let authorizationURL: String

    public init(authorizationURL: String) {
        self.authorizationURL = authorizationURL
    }
}

/// Result of handling an incoming OIDC authorization-code redirect callback.
public enum OIDCRedirectAuthResult: Sendable {
    case completed(CompleteAuthResult)
    case notOIDCRedirectCallback
    case noPendingAuth
}

enum OIDCRedirectAuthError: Error, Equatable, Sendable {
    case invalidAuthorizationURL(String)
    case randomBytesUnavailable
    case invalidState
    case stateNonceMismatch
    case stateScopeMismatch
    case stateRedirectUriMismatch
    case missingProviderRedirectURI
    case missingOMSRelayReturnURI
    case providerError(String)
    case missingCode
    case signerMismatch
    case staleFlow
}

extension OIDCRedirectAuthError: LocalizedError {
    var errorDescription: String? {
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
        case .missingProviderRedirectURI:
            return "OIDC provider redirect URI is required."
        case .missingOMSRelayReturnURI:
            return "OMS relay return URI is required."
        case .providerError(let message):
            return message
        case .missingCode:
            return "OIDC callback URL is missing code."
        case .signerMismatch:
            return "OIDC redirect auth signer mismatch."
        case .staleFlow:
            return "OIDC redirect auth flow is stale."
        }
    }
}

struct PendingOIDCRedirectAuth: Codable, Sendable {
    let verifier: String
    let challenge: String
    let nonce: String
    let authMode: OIDCAuthMode
    let redirectUri: String
    let issuer: String
    let provider: String?
    let providerLabel: String?
    let authorizationScope: String
    let walletType: WalletType
    let walletSelection: WalletSelectionBehavior?
    let sessionLifetimeSeconds: UInt32?
    let signerCredentialId: String
    let signerKeyType: SigningAlgorithm
    var consumed: Bool? = nil

    var isConsumed: Bool {
        consumed == true
    }

    var flowIdentifier: String {
        "\(nonce):\(verifier)"
    }

    func markingConsumed() -> PendingOIDCRedirectAuth {
        var pending = self
        pending.consumed = true
        return pending
    }
}

protocol OIDCRedirectAuthStore: Sendable {
    func load() throws -> PendingOIDCRedirectAuth?
    func save(_ pending: PendingOIDCRedirectAuth) throws
    func clear() throws
}

enum OIDCRedirectAuthLockRegistry {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var locks: [String: NSRecursiveLock] = [:]

    static func lock(for key: String) -> NSRecursiveLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[key] {
            return existing
        }
        let lock = NSRecursiveLock()
        locks[key] = lock
        return lock
    }
}

@available(macOS 12.0, iOS 15.0, *)
final class KeychainOIDCRedirectAuthStore: OIDCRedirectAuthStore, @unchecked Sendable {
    private let keychain: any KeychainManaging
    private let storageKey: String

    init(
        projectId: String,
        environment: OMSWalletEnvironment,
        keychain: any KeychainManaging = KeychainManager()
    ) {
        self.keychain = keychain
        self.storageKey = Constants.oidcRedirectAuthStorageKey(environment: environment, scope: projectId)
    }

    func load() throws -> PendingOIDCRedirectAuth? {
        guard let json = try keychain.string(forKey: storageKey) else {
            return nil
        }
        return try PendingOIDCRedirectAuth.from(jsonString: json)
    }

    func save(_ pending: PendingOIDCRedirectAuth) throws {
        try keychain.set(pending.jsonString(), forKey: storageKey)
    }

    func clear() throws {
        try keychain.delete(forKey: storageKey)
    }
}

struct OIDCCallbackParams: Sendable {
    let code: String?
    let state: String?
    let error: String?
    let errorDescription: String?

    var hasOidcResponse: Bool {
        code != nil || state != nil || error != nil || errorDescription != nil
    }
}

private struct OIDCStatePayload: Codable {
    let nonce: String
    let scope: String
    let redirectUri: String?

    enum CodingKeys: String, CodingKey {
        case nonce
        case scope
        case redirectUri = "redirect_uri"
    }
}

enum OIDCRedirectAuth {
    static func generateNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw OIDCRedirectAuthError.randomBytesUnavailable
        }
        return base64UrlEncode(Data(bytes))
    }

    static func encodeState(
        nonce: String,
        scope: String,
        redirectUri: String? = nil
    ) throws -> String {
        let payload = OIDCStatePayload(
            nonce: nonce,
            scope: scope,
            redirectUri: redirectUri
        )
        return base64UrlEncode(try WebRPCJSON.makeEncoder().encode(payload))
    }

    static func buildAuthorizationURL(
        provider: ResolvedOIDCProviderConfiguration,
        redirectURI: String,
        state: String,
        challenge: String,
        loginHint: String?,
        authMode: OIDCAuthMode,
        authorizeParams: [String: String]
    ) throws -> String {
        guard var components = URLComponents(string: provider.authorizationURL) else {
            throw OIDCRedirectAuthError.invalidAuthorizationURL(provider.authorizationURL)
        }

        var queryItems = components.queryItems ?? []
        func setQueryParameter(_ name: String, _ value: String) {
            queryItems.removeAll { $0.name == name }
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        func removeQueryParameter(_ name: String) {
            queryItems.removeAll { $0.name == name }
        }

        for (key, value) in authorizeParams {
            setQueryParameter(key, value)
        }
        if let loginHint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines), !loginHint.isEmpty {
            setQueryParameter("login_hint", loginHint)
        }

        setQueryParameter("client_id", provider.clientID)
        setQueryParameter("redirect_uri", redirectURI)
        setQueryParameter("response_type", "code")
        if provider.scopes.isEmpty {
            removeQueryParameter("scope")
        } else {
            setQueryParameter("scope", provider.scopes.joined(separator: " "))
        }
        setQueryParameter("state", state)
        if authMode == .authCodePKCE {
            setQueryParameter("code_challenge", challenge)
            setQueryParameter("code_challenge_method", "S256")
        } else {
            removeQueryParameter("code_challenge")
            removeQueryParameter("code_challenge_method")
        }

        components.queryItems = queryItems
        guard let url = components.url?.absoluteString else {
            throw OIDCRedirectAuthError.invalidAuthorizationURL(provider.authorizationURL)
        }
        return url
    }

    static func parseCallbackURL(_ callbackURL: String) -> OIDCCallbackParams {
        let query = callbackURL
            .substring(after: "?")
            .substring(before: "#")
        let fragment = callbackURL.substring(after: "#")
        let params = parseQuery(query).merging(parseQuery(fragment)) { queryValue, _ in queryValue }

        return OIDCCallbackParams(
            code: params["code"],
            state: params["state"],
            error: params["error"],
            errorDescription: params["error_description"]
        )
    }

    static func validateState(
        _ encodedState: String,
        pending: PendingOIDCRedirectAuth
    ) throws {
        let state = try decodeState(encodedState)
        guard state.nonce == pending.nonce else {
            throw OIDCRedirectAuthError.stateNonceMismatch
        }
        guard state.scope == pending.authorizationScope else {
            throw OIDCRedirectAuthError.stateScopeMismatch
        }
        guard state.redirectUri == nil || state.redirectUri == pending.redirectUri else {
            throw OIDCRedirectAuthError.stateRedirectUriMismatch
        }
    }

    static func matchesRedirectURI(callbackURL: String, redirectURI: String) -> Bool {
        guard let callback = URLComponents(string: callbackURL),
              let expected = URLComponents(string: redirectURI) else {
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

    private static func decodeState(_ encodedState: String) throws -> OIDCStatePayload {
        guard let data = base64UrlDecode(encodedState) else {
            throw OIDCRedirectAuthError.invalidState
        }
        do {
            return try WebRPCJSON.makeDecoder().decode(OIDCStatePayload.self, from: data)
        } catch {
            throw OIDCRedirectAuthError.invalidState
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
