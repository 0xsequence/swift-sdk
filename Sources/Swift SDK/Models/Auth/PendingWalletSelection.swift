import Foundation

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
            throw OmsSdkError.walletSelectionUnavailable()
        }
        return try await selectWalletAction(walletId)
    }

    @discardableResult
    public func createAndSelectWallet(reference: String? = nil) async throws -> WalletActivationResult {
        try await createAndSelectWalletAction(reference)
    }
}
