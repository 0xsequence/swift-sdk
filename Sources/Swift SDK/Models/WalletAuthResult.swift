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
public enum WalletSelectionBehavior: Equatable, Sendable {
    case automatic
    case manual
}

@available(macOS 12.0, iOS 15.0, *)
public final class PendingWalletSelection: @unchecked Sendable {
    public let walletType: WalletType
    public let wallets: [Wallet]
    public let credential: CredentialInfo

    private let selectWalletAction: (String) async throws -> WalletActivationResult
    private let createAndSelectWalletAction: (String?) async throws -> WalletActivationResult

    init(
        walletType: WalletType,
        wallets: [Wallet],
        credential: CredentialInfo,
        selectWalletAction: @escaping (String) async throws -> WalletActivationResult,
        createAndSelectWalletAction: @escaping (String?) async throws -> WalletActivationResult
    ) {
        self.walletType = walletType
        self.wallets = wallets
        self.credential = credential
        self.selectWalletAction = selectWalletAction
        self.createAndSelectWalletAction = createAndSelectWalletAction
    }

    @discardableResult
    public func selectWallet(walletId: String) async throws -> WalletActivationResult {
        guard wallets.contains(where: { $0.id == walletId }) else {
            throw WalletAuthError.selectedWalletUnavailable
        }
        return try await selectWalletAction(walletId)
    }

    @discardableResult
    public func createAndSelectWallet(reference: String? = nil) async throws -> WalletActivationResult {
        try await createAndSelectWalletAction(reference)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public enum CompleteAuthResult: Sendable {
    case walletSelected(
        walletAddress: String,
        wallet: Wallet,
        wallets: [Wallet],
        credential: CredentialInfo
    )
    case walletSelection(PendingWalletSelection)

    public var wallets: [Wallet] {
        switch self {
        case .walletSelected(_, _, let wallets, _):
            return wallets
        case .walletSelection(let pendingSelection):
            return pendingSelection.wallets
        }
    }

    public var credential: CredentialInfo {
        switch self {
        case .walletSelected(_, _, _, let credential):
            return credential
        case .walletSelection(let pendingSelection):
            return pendingSelection.credential
        }
    }

    public var walletAddress: String? {
        switch self {
        case .walletSelected(let walletAddress, _, _, _):
            return walletAddress
        case .walletSelection:
            return nil
        }
    }

    public var wallet: Wallet? {
        switch self {
        case .walletSelected(_, let wallet, _, _):
            return wallet
        case .walletSelection:
            return nil
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public enum WalletAuthError: Error, Equatable, Sendable {
    case selectedWalletUnavailable
    case noAuthenticatedWalletSession
    case noActiveCredential
}

@available(macOS 12.0, iOS 15.0, *)
extension WalletAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .selectedWalletUnavailable:
            return "Selected wallet is not one of the available options."
        case .noAuthenticatedWalletSession:
            return "No authenticated wallet session."
        case .noActiveCredential:
            return "No active credential."
        }
    }
}
