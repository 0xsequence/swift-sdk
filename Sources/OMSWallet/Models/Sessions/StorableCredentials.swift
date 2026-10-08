import Foundation

/// The persisted wallet-session record. Version 1 records (SDK 0.3.x) stored only the wallet ID and
/// address, without the wallet type; they fail to decode and are discarded, so users sign in again.
struct StorableCredentials: Codable {
    static let currentVersion = 2

    let version: Int
    let wallet: Wallet
    let signerCredentialId: String
    let alg: SigningAlgorithm
    let expiresAt: String?
    let auth: OMSWalletSessionAuth

    init(
        wallet: Wallet,
        signerCredentialId: String,
        alg: SigningAlgorithm,
        expiresAt: String? = nil,
        auth: OMSWalletSessionAuth
    ) {
        self.version = Self.currentVersion
        self.wallet = wallet
        self.signerCredentialId = signerCredentialId
        self.alg = alg
        self.expiresAt = expiresAt
        self.auth = auth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported stored session version: \(version)"
            )
        }
        let wallet = try container.decode(Wallet.self, forKey: .wallet)
        guard Self.isValidStoredWallet(wallet) else {
            throw DecodingError.dataCorruptedError(
                forKey: .wallet,
                in: container,
                debugDescription: "Stored session has an invalid wallet"
            )
        }
        self.version = version
        self.wallet = wallet
        self.signerCredentialId = try container.decode(String.self, forKey: .signerCredentialId)
        self.alg = try container.decode(SigningAlgorithm.self, forKey: .alg)
        self.expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        self.auth = try container.decode(OMSWalletSessionAuth.self, forKey: .auth)
    }

    private static func isValidStoredWallet(_ wallet: Wallet) -> Bool {
        guard !wallet.id.isEmpty, !wallet.address.isEmpty else {
            return false
        }
        switch wallet.keyOrigin {
        case .enclave, .imported:
            break
        case .unknown:
            return false
        }
        switch wallet.type {
        case .ethereum:
            return isEthereumAddressValue(wallet.address)
        case .solana, .tron:
            return true
        case .unknown:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case wallet
        case signerCredentialId
        case alg
        case expiresAt
        case auth
    }
}
