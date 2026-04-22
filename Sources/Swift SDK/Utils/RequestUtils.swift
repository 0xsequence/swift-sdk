import Foundation
import CryptoKit

@available(macOS 12.0, iOS 15.0, *)
public class RequestUtils {
    public static func buildWalletRequestPreimage(
        endpoint: String,
        nonce: String,
        payload: String
    ) -> String {
        return "POST /rpc/Wallet\(endpoint)\nnonce: \(nonce)\n\n\(payload)"
    }
    
    public static func buildAuthorizationHeader(
        scope: String,
        cred: String,
        nonce: String,
        sig: String
    ) -> String {
        return "ethereum-secp256k1 scope=\"\(scope)\",cred=\"\(cred)\",nonce=\(nonce),sig=\"\(sig)\""
    }
    
    public static func hashEmailAuthAnswer(
        challenge: String,
        code: String
    ) -> String {
        let inputData = Data("\(challenge)\(code)".utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashData = Data(hashed)
        let base64Hash = Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return base64Hash
    }
}
