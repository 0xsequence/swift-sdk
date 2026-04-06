import Foundation
import CryptoKit
import libsecp256k1

public class EthereumSigner {

    public enum SignerError: Error {
        case invalidKeyLength
        case invalidHashLength
        case signingFailed
    }
    
    public static func signUTF8MessageEIP191(privateKey: [UInt8], message: String) throws -> String {
        let hash = eip191Hash(message)
        return try signHash(privateKey: privateKey, hash32: hash)
    }

    /// Returns the EIP-191 digest as a 0x-prefixed hex string (without signing)
    public static func eip191Digest(message: String) -> String {
        let hash = eip191Hash(message)
        return "0x" + hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - EIP-191 Prefix + Hash

    private static func eip191Hash(_ message: String) -> [UInt8] {
        let messageBytes  = Array(message.utf8)
        let prefix        = "\u{19}Ethereum Signed Message:\n\(messageBytes.count)"
        let prefixed      = Array(prefix.utf8) + messageBytes
        return Keccak256.keccak256Bytes(prefixed)
    }

    // MARK: - secp256k1 Recoverable Sign
    private static func signHash(privateKey: [UInt8], hash32: [UInt8]) throws -> String {
        guard let ctx = secp256k1_context_create(
            UInt32(SECP256K1_CONTEXT_SIGN) | UInt32(SECP256K1_CONTEXT_VERIFY)
        ) else { throw SignerError.signingFailed }
        defer { secp256k1_context_destroy(ctx) }

        var rsig    = secp256k1_ecdsa_recoverable_signature()
        var seckey  = privateKey
        var digest  = hash32

        guard secp256k1_ecdsa_sign_recoverable(ctx, &rsig, &digest, &seckey, nil, nil) == 1 else {
            throw SignerError.signingFailed
        }

        var compact = [UInt8](repeating: 0, count: 64)
        var recid: Int32 = 0
        secp256k1_ecdsa_recoverable_signature_serialize_compact(ctx, &compact, &recid, &rsig)

        // Low-s normalize
        var nsig = secp256k1_ecdsa_signature()
        var nsigNorm = secp256k1_ecdsa_signature()
        secp256k1_ecdsa_recoverable_signature_convert(ctx, &nsig, &rsig)
        if secp256k1_ecdsa_signature_normalize(ctx, &nsigNorm, &nsig) != 0 {
            secp256k1_ecdsa_signature_serialize_compact(ctx, &compact, &nsigNorm)
            recid ^= 1
        }

        var sig65 = compact
        sig65.append(UInt8(recid + 27))
        return "0x" + sig65.map { String(format: "%02x", $0) }.joined()
    }

    // Negate s over the secp256k1 curve order n
    private static func negateS(_ s: Data) -> Data {
        let n: [UInt8] = [
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
            0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b,
            0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41
        ]
        var result = [UInt8](repeating: 0, count: 32)
        var borrow: Int = 0
        for i in stride(from: 31, through: 0, by: -1) {
            let diff = Int(n[i]) - Int(s[i]) - borrow
            result[i] = UInt8(bitPattern: Int8(truncatingIfNeeded: diff))
            borrow = diff < 0 ? 1 : 0
        }
        return Data(result)
    }
}
