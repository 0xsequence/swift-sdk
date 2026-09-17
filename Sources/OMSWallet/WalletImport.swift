import CryptoKit
import Foundation

public enum WalletImportCipherSuite: String, CaseIterable, Sendable {
    case x25519Sha256Aes256Gcm = "x25519-sha256-aes256gcm"
    case x25519Sha256ChaCha20Poly1305 = "x25519-sha256-chacha20poly1305"
    case p256Sha256Aes256Gcm = "p256-sha256-aes256gcm"
    case p256Sha256ChaCha20Poly1305 = "p256-sha256-chacha20poly1305"
}

public enum WalletImportPrivateKey: Sendable {
    case ethereum(String)
    case ethereumBytes(Data)
    case solana(String)
    case solanaBytes(Data)

    var walletType: WalletType {
        switch self {
        case .ethereum, .ethereumBytes: .ethereum
        case .solana, .solanaBytes: .solana
        }
    }
}

public struct WalletImportRecipientKey: Equatable, Sendable {
    public let keyId: String
    public let cipherSuite: WalletImportCipherSuite
    public let publicKey: String

    public init(keyId: String, cipherSuite: WalletImportCipherSuite, publicKey: String) {
        self.keyId = keyId
        self.cipherSuite = cipherSuite
        self.publicKey = publicKey
    }
}

public struct EncryptedWalletImportKeyMaterial: Equatable, Sendable {
    public let keyId: String
    public let cipherSuite: WalletImportCipherSuite
    public let encapsulatedKey: String
    public let ciphertext: String

    public init(
        keyId: String,
        cipherSuite: WalletImportCipherSuite,
        encapsulatedKey: String,
        ciphertext: String
    ) {
        self.keyId = keyId
        self.cipherSuite = cipherSuite
        self.encapsulatedKey = encapsulatedKey
        self.ciphertext = ciphertext
    }
}

extension WalletType {
    var waasNetworkFamily: WaasGenerated.NetworkFamily {
        switch self {
        case .ethereum: .evm
        case .solana: .solana
        case .unknown(let value): .unknown(value)
        }
    }
}

enum WalletImportValidation {
    private static let secp256k1Order: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
        0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b,
        0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41
    ]
    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func plaintext(_ privateKey: WalletImportPrivateKey) throws -> Data {
        switch privateKey {
        case .ethereum(let value):
            let trimmed = trimAsciiWhitespace(value)
            let hex = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit), let bytes = Data(hexString: hex) else {
                throw validation("Ethereum privateKey must be 32 bytes or 64 hexadecimal characters")
            }
            try requireValidEthereumScalar(bytes)
            return Data(trimmed.utf8)
        case .ethereumBytes(let bytes):
            guard bytes.count == 32 else {
                throw validation("Ethereum privateKey must contain exactly 32 bytes")
            }
            try requireValidEthereumScalar(bytes)
            return bytes
        case .solana(let value):
            let trimmed = trimAsciiWhitespace(value)
            guard let decoded = decodeBase58(trimmed), decoded.count == 32 || decoded.count == 64 else {
                throw validation("Solana privateKey must decode to a 32-byte seed or 64-byte keypair")
            }
            guard trimmed.count != 32 && trimmed.count != 64 else {
                throw validation("Solana privateKey string is ambiguous; provide the raw bytes instead")
            }
            return Data(trimmed.utf8)
        case .solanaBytes(let bytes):
            guard bytes.count == 32 || bytes.count == 64 else {
                throw validation("Solana privateKey must contain a 32-byte seed or 64-byte keypair")
            }
            return bytes
        }
    }

    static func validateReference(_ reference: String?) throws {
        guard let reference else { return }
        guard reference.lengthOfBytes(using: .utf8) <= 128 else {
            throw validation("reference must be at most 128 UTF-8 bytes")
        }
    }

    static func canonicalBase64(_ value: String, field: String) throws -> String {
        guard let data = Data(base64Encoded: value), !data.isEmpty, data.base64EncodedString() == value else {
            throw validation("\(field) must be canonical base64")
        }
        return value
    }

    private static func requireValidEthereumScalar(_ value: Data) throws {
        let bytes = [UInt8](value)
        guard bytes.contains(where: { $0 != 0 }), bytes.lexicographicallyPrecedes(secp256k1Order) else {
            throw validation("Ethereum privateKey is outside the valid secp256k1 scalar range")
        }
    }

    private static func decodeBase58(_ value: String) -> Data? {
        guard !value.isEmpty else { return nil }
        var bytes: [UInt8] = [0]
        for character in value {
            guard let digit = base58Alphabet.firstIndex(of: character) else { return nil }
            var carry = digit
            for index in bytes.indices.reversed() {
                let current = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(current & 0xff)
                carry = current >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }
        let leadingZeros = value.prefix(while: { $0 == "1" }).count
        let significant = bytes.drop(while: { $0 == 0 })
        return Data(repeating: 0, count: leadingZeros) + Data(significant)
    }

    private static func validation(_ message: String) -> OMSWalletError {
        OMSWalletError(code: .validationError, message: message)
    }

    private static func trimAsciiWhitespace(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\t\n\u{000C}\r "))
    }
}

enum P256HPKE {
    static func seal(recipientPublicKey: Data, plaintext: Data) throws -> (encapsulatedKey: Data, ciphertext: Data) {
        let recipient = try P256.KeyAgreement.PublicKey(derRepresentation: recipientPublicKey)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let encapsulatedKey = ephemeral.publicKey.x963Representation
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let dh = sharedSecret.withUnsafeBytes { Data($0) }

        let kemSuiteId = Data("KEM".utf8) + uint16(0x0010)
        let kemContext = encapsulatedKey + recipient.x963Representation
        let eaePrk = labeledExtract(salt: Data(), suiteId: kemSuiteId, label: "eae_prk", ikm: dh)
        let shared = try labeledExpand(prk: eaePrk, suiteId: kemSuiteId, label: "shared_secret", info: kemContext, length: 32)

        let suiteId = Data("HPKE".utf8) + uint16(0x0010) + uint16(0x0001) + uint16(0x0002)
        let pskIdHash = labeledExtract(salt: Data(), suiteId: suiteId, label: "psk_id_hash", ikm: Data())
        let infoHash = labeledExtract(salt: Data(), suiteId: suiteId, label: "info_hash", ikm: Data())
        let context = Data([0]) + pskIdHash + infoHash
        let secret = labeledExtract(salt: shared, suiteId: suiteId, label: "secret", ikm: Data())
        let key = try labeledExpand(prk: secret, suiteId: suiteId, label: "key", info: context, length: 32)
        let nonce = try labeledExpand(prk: secret, suiteId: suiteId, label: "base_nonce", info: context, length: 12)

        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: AES.GCM.Nonce(data: nonce),
            authenticating: Data()
        )
        return (encapsulatedKey, sealed.ciphertext + sealed.tag)
    }

    private static func labeledExtract(salt: Data, suiteId: Data, label: String, ikm: Data) -> Data {
        hkdfExtract(salt: salt, ikm: Data("HPKE-v1".utf8) + suiteId + Data(label.utf8) + ikm)
    }

    private static func labeledExpand(prk: Data, suiteId: Data, label: String, info: Data, length: Int) throws -> Data {
        let labeledInfo = uint16(UInt16(length)) + Data("HPKE-v1".utf8) + suiteId + Data(label.utf8) + info
        return try hkdfExpand(prk: prk, info: labeledInfo, length: length)
    }

    private static func hkdfExtract(salt: Data, ikm: Data) -> Data {
        let key = SymmetricKey(data: salt.isEmpty ? Data(repeating: 0, count: 32) : salt)
        return Data(HMAC<SHA256>.authenticationCode(for: ikm, using: key))
    }

    private static func hkdfExpand(prk: Data, info: Data, length: Int) throws -> Data {
        guard length <= 255 * 32 else { throw OMSWalletError(code: .validationError, message: "HPKE output is too long") }
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < length {
            previous = Data(HMAC<SHA256>.authenticationCode(
                for: previous + info + Data([counter]),
                using: SymmetricKey(data: prk)
            ))
            output += previous
            counter &+= 1
        }
        return output.prefix(length)
    }

    private static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
