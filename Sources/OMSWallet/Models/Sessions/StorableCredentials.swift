import Foundation

/// The persisted wallet-session record. Version 1 records (SDK 0.3.x) stored only the wallet ID and
/// address, without the wallet type; they fail to decode and are discarded, so users sign in again.
/// The lifetime cap was added within version 2 (pre-release 0.4.0 records lack it); a record
/// without a valid cap fails to decode and is discarded like any invalid record, so the user signs
/// in again. Pre-release records also stored an `idleWindowSeconds`, which is ignored.
struct StorableCredentials: Codable {
    static let currentVersion = 2

    let version: Int
    let wallet: Wallet
    let signerCredentialId: String
    let alg: SigningAlgorithm
    let expiresAt: String
    let auth: OMSWalletSessionAuth
    /// `SessionExpiryBounds.ceiling`, in seconds since 1970. Optional only so that a session whose
    /// cap is unknown can still be written; such a record is discarded on restore.
    let expiryCeilingEpochSeconds: Double?

    init(
        wallet: Wallet,
        signerCredentialId: String,
        alg: SigningAlgorithm,
        expiresAt: String,
        auth: OMSWalletSessionAuth,
        expiryBounds: SessionExpiryBounds? = nil
    ) {
        self.version = Self.currentVersion
        self.wallet = wallet
        self.signerCredentialId = signerCredentialId
        self.alg = alg
        self.expiresAt = expiresAt
        self.auth = auth
        self.expiryCeilingEpochSeconds = expiryBounds?.ceilingEpochSeconds
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
        self.expiresAt = try container.decode(String.self, forKey: .expiresAt)
        self.auth = try container.decode(OMSWalletSessionAuth.self, forKey: .auth)
        guard let expiryBounds = SessionExpiryBounds(
            ceilingEpochSeconds: try container.decodeIfPresent(Double.self, forKey: .expiryCeilingEpochSeconds)
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiryCeilingEpochSeconds,
                in: container,
                debugDescription: "Stored session has no valid lifetime cap"
            )
        }
        self.expiryCeilingEpochSeconds = expiryBounds.ceilingEpochSeconds
    }

    /// This record with its expiry replaced by `expiresAt`.
    func expiring(at expiresAt: String) -> StorableCredentials {
        StorableCredentials(
            wallet: wallet,
            signerCredentialId: signerCredentialId,
            alg: alg,
            expiresAt: expiresAt,
            auth: auth,
            expiryBounds: expiryBounds
        )
    }

    var expiryBounds: SessionExpiryBounds? {
        SessionExpiryBounds(ceilingEpochSeconds: expiryCeilingEpochSeconds)
    }

    /// Sign-in uses the same rule, so it never activates a wallet that restore would discard.
    static func isValidStoredWallet(_ wallet: Wallet) -> Bool {
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
}
