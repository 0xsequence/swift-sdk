import Foundation

@available(macOS 12.0, iOS 15.0, *)
public final class PendingWalletSelection: @unchecked Sendable {
    public let walletType: WalletType
    public let wallets: [Wallet]
    /// Wallets of `walletType` preallocated for the signed-in user that they can claim with
    /// `WalletClient.claimWallet(walletId:)`.
    public let claimableWallets: [Wallet]
    public let credential: WalletCredential

    private let selectWalletAction: (String) async throws -> WalletActivationResult
    private let createAndSelectWalletAction: (String?) async throws -> WalletActivationResult
    private let claimAndSelectWalletAction: (String) async throws -> WalletActivationResult
    private let actionLock = NSLock()
    private var actionInFlight = false

    init(
        walletType: WalletType,
        wallets: [Wallet],
        claimableWallets: [Wallet],
        credential: WalletCredential,
        selectWalletAction: @escaping (String) async throws -> WalletActivationResult,
        createAndSelectWalletAction: @escaping (String?) async throws -> WalletActivationResult,
        claimAndSelectWalletAction: @escaping (String) async throws -> WalletActivationResult
    ) {
        self.walletType = walletType
        self.wallets = wallets
        self.claimableWallets = claimableWallets
        self.credential = credential
        self.selectWalletAction = selectWalletAction
        self.createAndSelectWalletAction = createAndSelectWalletAction
        self.claimAndSelectWalletAction = claimAndSelectWalletAction
    }

    @discardableResult
    public func selectWallet(walletId: String) async throws -> WalletActivationResult {
        try await runOMSWalletOperation(.pendingWalletSelectionSelectWallet) {
            guard wallets.contains(where: { $0.id == walletId }) else {
                throw OMSWalletError.walletSelectionUnavailable()
            }
            return try await runSelectionAction {
                try await selectWalletAction(walletId)
            }
        }
    }

    @discardableResult
    public func createAndSelectWallet(reference: String? = nil) async throws -> WalletActivationResult {
        try await runOMSWalletOperation(.pendingWalletSelectionCreateAndSelectWallet) {
            try await runSelectionAction {
                try await createAndSelectWalletAction(reference)
            }
        }
    }

    /// Claims one of `claimableWallets` and selects it, completing this selection.
    ///
    /// An ID that is not in `claimableWallets` throws `.walletSelectionUnavailable` without a request.
    @discardableResult
    public func claimAndSelectWallet(walletId: String) async throws -> WalletActivationResult {
        try await runOMSWalletOperation(.pendingWalletSelectionClaimAndSelectWallet) {
            guard claimableWallets.contains(where: { $0.id == walletId }) else {
                throw OMSWalletError.walletSelectionUnavailable()
            }
            return try await runSelectionAction {
                try await claimAndSelectWalletAction(walletId)
            }
        }
    }

    private func runSelectionAction<T>(_ action: () async throws -> T) async throws -> T {
        try beginSelectionAction()
        defer {
            endSelectionAction()
        }
        return try await action()
    }

    private func beginSelectionAction() throws {
        actionLock.lock()
        defer { actionLock.unlock() }
        guard !actionInFlight else {
            throw OMSWalletError.walletSelectionInFlight()
        }
        actionInFlight = true
    }

    private func endSelectionAction() {
        actionLock.lock()
        actionInFlight = false
        actionLock.unlock()
    }
}
