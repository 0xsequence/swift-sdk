import Foundation

public class RequestUtils {
    public static func BuildWalletRequestPreimage(
        endpoint: String,
        nonce: String,
        payload: String
    ) -> String {
        return "POST /rpc/Wallet\(endpoint)\nnonce: \(nonce)\n\n\(payload)"
    }
    
    public static func BuildAuthorizationHeader(
        scope: String,
        cred: String,
        nonce: String,
        sig: String
    ) -> String {
        return "Authorization: Ethereum_Secp256k1 scope=\"\(scope)\",cred=\"\(cred)\",nonce=\(nonce),sig=\"\(sig)\""
    }
}
