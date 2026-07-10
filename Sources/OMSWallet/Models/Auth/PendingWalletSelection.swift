import Foundation

@available(macOS 12.0, iOS 15.0, *)
public final class PendingWalletSelection: @unchecked Sendable {
    public let walletType: WalletType
    public let wallets: [Wallet]
    public let credential: CredentialInfo

    private let selectWalletAction: (String) async throws -> WalletSelectionResult
    private let createAndSelectWalletAction: (String?) async throws -> WalletSelectionResult
    private let actionLock = NSLock()
    private var actionInFlight = false

    init(
        walletType: WalletType,
        wallets: [Wallet],
        credential: CredentialInfo,
        selectWalletAction: @escaping (String) async throws -> WalletSelectionResult,
        createAndSelectWalletAction: @escaping (String?) async throws -> WalletSelectionResult
    ) {
        self.walletType = walletType
        self.wallets = wallets
        self.credential = credential
        self.selectWalletAction = selectWalletAction
        self.createAndSelectWalletAction = createAndSelectWalletAction
    }

    @discardableResult
    public func selectWallet(walletId: String) async throws -> WalletSelectionResult {
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
    public func createAndSelectWallet(reference: String? = nil) async throws -> WalletSelectionResult {
        try await runOMSWalletOperation(.pendingWalletSelectionCreateAndSelectWallet) {
            try await runSelectionAction {
                try await createAndSelectWalletAction(reference)
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
