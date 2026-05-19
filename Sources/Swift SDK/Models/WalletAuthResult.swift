import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct WalletActivationResult: Sendable {
    public let walletAddress: String
    public let wallet: Wallet

    public init(walletAddress: String, wallet: Wallet) {
        self.walletAddress = walletAddress
        self.wallet = wallet
    }
}

@available(macOS 12.0, iOS 15.0, *)
public enum CompleteAuthResult: Sendable {
    case activated(
        walletAddress: String,
        wallet: Wallet,
        wallets: [Wallet],
        credential: CredentialInfo
    )
    case walletSelection(
        wallets: [Wallet],
        credential: CredentialInfo
    )

    public var wallets: [Wallet] {
        switch self {
        case .activated(_, _, let wallets, _),
             .walletSelection(let wallets, _):
            return wallets
        }
    }

    public var credential: CredentialInfo {
        switch self {
        case .activated(_, _, _, let credential),
             .walletSelection(_, let credential):
            return credential
        }
    }

    public var walletAddress: String? {
        switch self {
        case .activated(let walletAddress, _, _, _):
            return walletAddress
        case .walletSelection:
            return nil
        }
    }

    public var wallet: Wallet? {
        switch self {
        case .activated(_, let wallet, _, _):
            return wallet
        case .walletSelection:
            return nil
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public enum WalletAuthError: Error, Equatable, Sendable {
    case multipleWalletsAvailable
    case selectedWalletUnavailable
    case authCompletedWithoutWalletActivation
    case noAuthenticatedWalletSession
    case noActiveCredential
}

@available(macOS 12.0, iOS 15.0, *)
extension WalletAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .multipleWalletsAvailable:
            return "Multiple wallets are available. Call completeEmailAuth(code:walletType:selectWallet:) to choose one."
        case .selectedWalletUnavailable:
            return "Selected wallet is not one of the available options."
        case .authCompletedWithoutWalletActivation:
            return "Auth completed without wallet activation."
        case .noAuthenticatedWalletSession:
            return "No authenticated wallet session."
        case .noActiveCredential:
            return "No active credential."
        }
    }
}
