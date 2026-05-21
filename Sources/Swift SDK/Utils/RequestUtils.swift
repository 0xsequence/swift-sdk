import Foundation
import CryptoKit

@available(macOS 12.0, iOS 15.0, *)
public class RequestUtils {
    public static func buildWalletRequestPreimage(
        endpoint: String,
        nonce: String,
        scope: String,
        payload: String
    ) -> String {
        return "POST /rpc/Wallet\(endpoint)\nnonce: \(nonce)\nscope: \(scope)\n\n\(payload)"
    }
    
    public static func buildWalletSignatureHeader(
        alg: SigningAlgorithm,
        scope: String,
        cred: String,
        nonce: String,
        sig: String
    ) -> String {
        return "alg=\"\(alg.wireValue)\", scope=\"\(scope)\", cred=\"\(cred)\", nonce=\(nonce), sig=\"\(sig)\""
    }
    
    public static func hashEmailAuthAnswer(
        challenge: String,
        code: String
    ) -> String {
        let inputData = Data("\(challenge)\(code)".utf8)
        let hashed = SHA256.hash(data: inputData)
        let base64Hash = Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return base64Hash
    }
}

public enum OidcIdTokenError: Error, Equatable, Sendable {
    case missingPayload
    case invalidPayload
    case missingExpiration
    case invalidExpiration
}

extension OidcIdTokenError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "OIDC ID token must contain header and payload sections."
        case .invalidPayload:
            return "OIDC ID token payload is invalid."
        case .missingExpiration:
            return "OIDC ID token is missing an exp claim."
        case .invalidExpiration:
            return "OIDC ID token exp claim is invalid."
        }
    }
}

public enum OidcIdToken {
    public static func expiresAtEpochSeconds(_ idToken: String) throws -> Int64 {
        let payload = try parsePayload(idToken)
        guard let value = payload["exp"] else {
            throw OidcIdTokenError.missingExpiration
        }
        guard let expiration = epochSeconds(from: value) else {
            throw OidcIdTokenError.invalidExpiration
        }
        return expiration
    }

    public static func handleHash(_ idToken: String) -> String {
        let digest = SHA256.hash(data: Data(idToken.utf8))
        return base64UrlEncode(Data(digest))
    }

    private static func parsePayload(_ idToken: String) throws -> [String: Any] {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw OidcIdTokenError.missingPayload
        }
        guard let data = base64UrlDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            throw OidcIdTokenError.invalidPayload
        }
        return payload
    }

    private static func epochSeconds(from value: Any) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? UInt64, value <= UInt64(Int64.max) {
            return Int64(value)
        }
        if let value = value as? Double, value.rounded(.towardZero) == value {
            return Int64(value)
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
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
