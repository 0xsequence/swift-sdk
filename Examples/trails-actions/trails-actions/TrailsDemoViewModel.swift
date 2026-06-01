import Combine
import Foundation
import OMS_SDK

// Serializes OMS wallet/indexer access so the Swift 6 example never sends the
// mutable wallet client directly out of the MainActor view model.
private final class TrailsOMSStorage: @unchecked Sendable {
    let oms: OMSClient

    init(publishableKey: String, projectId: String) {
        self.oms = OMSClient(
            publishableKey: publishableKey,
            projectId: projectId
        )
    }
}

actor TrailsOMSClient {
    private let storage: TrailsOMSStorage
    private var tail: Task<Void, Never>?

    nonisolated let initialSession: SessionState

    init(publishableKey: String, projectId: String) {
        let storage = TrailsOMSStorage(publishableKey: publishableKey, projectId: projectId)
        self.storage = storage
        self.initialSession = storage.oms.wallet.session
    }

    func session() async -> SessionState {
        await perform { client in
            client.wallet.session
        }
    }

    func startEmailAuth(email: String) async throws {
        try await performThrowing { client in
            try await client.wallet.startEmailAuth(email: email)
        }
    }

    func completeEmailAuth(
        code: String,
        walletSelection: WalletSelectionBehavior
    ) async throws -> TrailsCompleteAuthResult {
        let result = try await performThrowing { client in
            try await client.wallet.completeEmailAuth(
                code: code,
                walletSelection: walletSelection
            )
        }
        return wrap(result)
    }

    func startOidcRedirectAuth(
        provider: OidcProviderConfig,
        redirectUri: String
    ) async throws -> StartOidcRedirectAuthResult {
        try await performThrowing { client in
            try await client.wallet.startOidcRedirectAuth(
                provider: provider,
                redirectUri: redirectUri
            )
        }
    }

    func handleOidcRedirectCallback(
        _ callbackUrl: String,
        walletSelection: WalletSelectionBehavior
    ) async throws -> TrailsOidcRedirectAuthResult {
        let result = try await performThrowing { client in
            try await client.wallet.handleOidcRedirectCallback(
                callbackUrl,
                walletSelection: walletSelection
            )
        }
        return wrap(result)
    }

    func signOut() async throws {
        try await performThrowing { client in
            try client.wallet.signOut()
        }
    }

    func getNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async throws -> TokenBalance? {
        try await performThrowing { client in
            try await client.indexer.getNativeTokenBalance(
                network: network,
                walletAddress: walletAddress
            )
        }
    }

    func getTokenBalances(
        network: Network,
        contractAddress: String,
        walletAddress: String,
        includeMetadata: Bool
    ) async throws -> TokenBalancesResult {
        try await performThrowing { client in
            try await client.indexer.getTokenBalances(
                network: network,
                contractAddress: contractAddress,
                walletAddress: walletAddress,
                includeMetadata: includeMetadata
            )
        }
    }

    func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        selectFeeOption: FeeOptionSelector
    ) async throws -> SendTransactionResponse {
        try await performThrowing { client in
            try await client.wallet.sendTransaction(
                network: network,
                request: request,
                selectFeeOption: selectFeeOption
            )
        }
    }

    func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse {
        try await performThrowing { client in
            try await client.wallet.getTransactionStatus(txnId: txnId)
        }
    }

    fileprivate func selectWallet(
        _ pendingSelection: PendingWalletSelection,
        walletId: String
    ) async throws -> WalletActivationResult {
        try await performThrowing { _ in
            try await pendingSelection.selectWallet(walletId: walletId)
        }
    }

    fileprivate func createAndSelectWallet(
        _ pendingSelection: PendingWalletSelection,
        reference: String?
    ) async throws -> WalletActivationResult {
        try await performThrowing { _ in
            try await pendingSelection.createAndSelectWallet(reference: reference)
        }
    }

    private func wrap(_ result: CompleteAuthResult) -> TrailsCompleteAuthResult {
        switch result {
        case .walletSelected(let walletAddress, let wallet, let wallets, let credential):
            return .walletSelected(
                walletAddress: walletAddress,
                wallet: wallet,
                wallets: wallets,
                credential: credential
            )
        case .walletSelection(let pendingSelection):
            return .walletSelection(
                TrailsPendingWalletSelection(pendingSelection, client: self)
            )
        }
    }

    private func wrap(_ result: OidcRedirectAuthResult) -> TrailsOidcRedirectAuthResult {
        switch result {
        case .completed(let wallet):
            return .completed(wallet: wallet)
        case .walletSelection(let pendingSelection):
            return .walletSelection(
                TrailsPendingWalletSelection(pendingSelection, client: self)
            )
        case .notOidcRedirectCallback:
            return .notOidcRedirectCallback
        case .noPendingAuth:
            return .noPendingAuth
        case .failed(let error):
            return .failed(error)
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (OMSClient) async -> T
    ) async -> T {
        let previous = tail
        let storage = storage
        let task = Task.detached {
            await previous?.value
            return await operation(storage.oms)
        }
        tail = Task {
            _ = await task.value
        }
        return await task.value
    }

    private func performThrowing<T: Sendable>(
        _ operation: @escaping @Sendable (OMSClient) async throws -> T
    ) async throws -> T {
        let previous = tail
        let storage = storage
        let task = Task.detached {
            await previous?.value
            return try await operation(storage.oms)
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await task.value
    }
}

enum TrailsCompleteAuthResult: Sendable {
    case walletSelected(
        walletAddress: String,
        wallet: Wallet,
        wallets: [Wallet],
        credential: CredentialInfo
    )
    case walletSelection(TrailsPendingWalletSelection)
}

enum TrailsOidcRedirectAuthResult: Sendable {
    case completed(wallet: Wallet)
    case walletSelection(TrailsPendingWalletSelection)
    case notOidcRedirectCallback
    case noPendingAuth
    case failed(Error)
}

final class TrailsPendingWalletSelection: @unchecked Sendable {
    let walletType: WalletType
    let wallets: [Wallet]
    let credential: CredentialInfo

    private let pendingSelection: PendingWalletSelection
    private let client: TrailsOMSClient

    init(_ pendingSelection: PendingWalletSelection, client: TrailsOMSClient) {
        self.walletType = pendingSelection.walletType
        self.wallets = pendingSelection.wallets
        self.credential = pendingSelection.credential
        self.pendingSelection = pendingSelection
        self.client = client
    }

    func selectWallet(walletId: String) async throws -> WalletActivationResult {
        try await client.selectWallet(pendingSelection, walletId: walletId)
    }

    func createAndSelectWallet(reference: String? = nil) async throws -> WalletActivationResult {
        try await client.createAndSelectWallet(pendingSelection, reference: reference)
    }
}

@MainActor
final class TrailsDemoViewModel: ObservableObject {
    @Published var session = SessionState(walletAddress: nil)
    @Published var authStep: AuthStep = .email
    @Published var email = ""
    @Published var code = ""
    @Published var pendingWalletSelection: TrailsPendingWalletSelection?
    @Published var useManualWalletSelection: Bool {
        didSet {
            UserDefaults.standard.set(useManualWalletSelection, forKey: manualWalletSelectionKey)
        }
    }
    @Published var authStatus = "Enter an email to start."
    @Published var redirectStatus = ""
    @Published var balances = BalanceState.signedOut
    @Published var earnPositions: [EarnPosition] = []
    @Published var earnPositionsStatus = "Sign in to load earn positions."
    @Published var swapPOLAmount = defaultSwapPOLAmount
    @Published var depositUSDCAmount = defaultDepositUSDCAmount
    @Published var earnPOLAmount = defaultEarnPOLAmount
    @Published var preparedSwap: PreparedSwapTransaction?
    @Published var preparedDeposit: PreparedYieldTransactions?
    @Published var preparedEarn: PreparedSwapAndEarnPlan?
    @Published var swapStatus = ""
    @Published var depositStatus = ""
    @Published var earnStatus = ""
    @Published var lastSwapTransaction: TransactionResultViewState?
    @Published var lastDepositTransaction: TransactionResultViewState?
    @Published var lastEarnTransaction: TransactionResultViewState?
    @Published var withdrawStatuses: [String: String] = [:]
    @Published var lastWithdrawTransactions: [String: TransactionResultViewState] = [:]
    @Published var feeOptionSelectionRequest: FeeOptionSelectionRequest?
    @Published var logLines = ["Ready."]
    @Published var loadingAction: String?
    @Published var error: AppError?
    @Published var safariAuthSession: SafariAuthSession?

    let oms = TrailsOMSClient(
        publishableKey: defaultPublishableKey,
        projectId: defaultProjectID
    )

    private let trailsClient = TrailsApiTrailsClient(
        baseURL: trailsAPIURL,
        headers: {
            [trailsAccessKeyHeader: trailsAccessKey]
        }
    )
    private let trailsIntentClient = TrailsIntentClient(
        baseURL: trailsAPIURL,
        headers: {
            [trailsAccessKeyHeader: trailsAccessKey]
        }
    )
    private var selectedFeeOption: FeeOptionWithBalance?
    private var preparedWithdraws: [String: PreparedYieldTransactions] = [:]
    private let manualWalletSelectionKey = "oms-trails-actions-manual-wallet-selection"

    init() {
        self.useManualWalletSelection = UserDefaults.standard.bool(forKey: manualWalletSelectionKey)
        self.session = oms.initialSession
        if isSignedIn {
            authStatus = "Wallet session restored."
            appendLog("Wallet ready: \(walletAddress ?? "")")
        }
    }

    var walletAddress: String? {
        session.walletAddress
    }

    var isSignedIn: Bool {
        walletAddress != nil
    }

    var isBusy: Bool {
        loadingAction != nil
    }

    var walletSelectionBehavior: WalletSelectionBehavior {
        useManualWalletSelection ? .manual : .automatic
    }

    func refreshSession() async {
        session = await oms.session()
    }

    func refreshAfterLaunch() async {
        await refreshSession()
        if let walletAddress {
            await refreshBalances(walletAddress: walletAddress)
            await refreshEarnPositions(walletAddress: walletAddress)
        }
    }

    func startEmailAuth() {
        Task {
            await runAction("Start email sign-in") {
                let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedEmail.isEmpty else {
                    throw TrailsDemoError(message: "Email is required.")
                }

                pendingWalletSelection = nil
                authStatus = "Requesting email code..."
                try await oms.startEmailAuth(email: normalizedEmail)
                email = ""
                authStep = .code
                authStatus = "Code requested for \(normalizedEmail)"
            } onFailure: { [self] error in
                authStatus = "Sign-in error: \(describe(error))"
            }
        }
    }

    func completeEmailAuth() {
        Task {
            await runAction("Complete email sign-in") {
                let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedCode.isEmpty else {
                    throw TrailsDemoError(message: "Code is required.")
                }

                authStatus = "Verifying code..."
                let result = try await oms.completeEmailAuth(
                    code: normalizedCode,
                    walletSelection: walletSelectionBehavior
                )
                code = ""
                authStep = .email
                await handleAuthCompletion(result, status: "Email login complete.")
            } onFailure: { [self] error in
                authStatus = "Verify error: \(describe(error))"
            }
        }
    }

    func startGoogleRedirectAuth() {
        Task {
            await runAction("Start Google sign-in") {
                pendingWalletSelection = nil
                redirectStatus = "Opening provider..."
                let started = try await oms.startOidcRedirectAuth(
                    provider: OidcProviders.google(),
                    redirectUri: trailsRedirectURI
                )
                guard let authorizationURL = URL(string: started.authorizationUrl) else {
                    throw TrailsDemoError.invalidAuthorizationURL
                }
                safariAuthSession = SafariAuthSession(url: authorizationURL)
            } onFailure: { [self] error in
                redirectStatus = "Google sign-in error: \(describe(error))"
            }
        }
    }

    func handleOpenURL(_ url: URL) async {
        await runAction("Complete Google sign-in") {
            let result = try await oms.handleOidcRedirectCallback(
                url.absoluteString,
                walletSelection: walletSelectionBehavior
            )

            switch result {
            case .completed:
                safariAuthSession = nil
                pendingWalletSelection = nil
                redirectStatus = "Google login complete."
                await refreshSession()
                appendLog("Wallet ready: \(walletAddress ?? "")")
                if let walletAddress {
                    await refreshBalances(walletAddress: walletAddress)
                    await refreshEarnPositions(walletAddress: walletAddress)
                }
            case .walletSelection(let pendingSelection):
                safariAuthSession = nil
                pendingWalletSelection = pendingSelection
                authStatus = "Choose a wallet to continue."
                redirectStatus = ""
            case .notOidcRedirectCallback, .noPendingAuth:
                break
            case .failed(let error):
                safariAuthSession = nil
                throw error
            }
        } onFailure: { [self] error in
            redirectStatus = "Google redirect error: \(describe(error))"
        }
    }

    func selectPendingWallet(_ wallet: Wallet) {
        guard let pendingWalletSelection else { return }
        Task {
            await runAction("Selecting wallet") {
                let result = try await pendingWalletSelection.selectWallet(walletId: wallet.id)
                await handleWalletActivation(result, status: "Wallet selected.")
            } onFailure: { [self] error in
                authStatus = "Wallet selection error: \(describe(error))"
            }
        }
    }

    func createPendingWallet() {
        guard let pendingWalletSelection else { return }
        Task {
            await runAction("Creating wallet") {
                let result = try await pendingWalletSelection.createAndSelectWallet(reference: "trails-actions")
                await handleWalletActivation(result, status: "Wallet created.")
            } onFailure: { [self] error in
                authStatus = "Wallet creation error: \(describe(error))"
            }
        }
    }

    func cancelPendingWalletSelection() {
        Task {
            await runAction("Cancel wallet selection") {
                try await oms.signOut()
                pendingWalletSelection = nil
                authStep = .email
                code = ""
                authStatus = "Enter an email to start."
                redirectStatus = ""
                clearPreparedState()
                await refreshSession()
            }
        }
    }

    func signOut() {
        Task {
            await runAction("Sign out") {
                try await oms.signOut()
                safariAuthSession = nil
                pendingWalletSelection = nil
                authStep = .email
                code = ""
                authStatus = "Signed out."
                redirectStatus = ""
                balances = .signedOut
                earnPositions = []
                earnPositionsStatus = "Sign in to load earn positions."
                clearPreparedState()
                await refreshSession()
            }
        }
    }

    func refreshSignedInData() {
        Task {
            await runAction("Refresh data") {
                _ = await refreshSignedInData(status: "Refreshing Polygon data...")
            }
        }
    }

    func updateSwapPOLAmount(_ value: String) {
        guard let normalized = normalizeAmountInput(value) else { return }
        cancelFeeSelection(message: "Amount changed")
        swapPOLAmount = normalized
        preparedSwap = nil
        lastSwapTransaction = nil
        swapStatus = ""
    }

    func updateDepositUSDCAmount(_ value: String) {
        guard let normalized = normalizeAmountInput(value) else { return }
        cancelFeeSelection(message: "Amount changed")
        depositUSDCAmount = normalized
        preparedDeposit = nil
        lastDepositTransaction = nil
        depositStatus = ""
    }

    func updateEarnPOLAmount(_ value: String) {
        guard let normalized = normalizeAmountInput(value) else { return }
        cancelFeeSelection(message: "Amount changed")
        earnPOLAmount = normalized
        preparedEarn = nil
        lastEarnTransaction = nil
        earnStatus = ""
    }

    func prepareSwap() {
        Task {
            await runAction("Prepare swap") {
                let prepared = try await prepareSwapPOLToUSDC(
                    walletAddress: requireWalletAddress(),
                    polAmount: swapPOLAmount
                )
                preparedSwap = prepared
                swapStatus = "Swap status: prepared Trails intent for about \(prepared.outputDisplay)."
            } onFailure: { [self] error in
                swapStatus = "Swap status: \(describe(error))"
            }
        }
    }

    func prepareDeposit() {
        Task {
            await runAction("Prepare deposit") {
                let prepared = try await prepareDepositUSDC(
                    walletAddress: requireWalletAddress(),
                    usdcAmount: depositUSDCAmount
                )
                preparedDeposit = prepared
                depositStatus = "Deposit status: prepared \(prepared.transactions.count) wallet transaction\(prepared.transactions.count == 1 ? "" : "s")."
            } onFailure: { [self] error in
                depositStatus = "Deposit status: \(describe(error))"
            }
        }
    }

    func prepareEarn() {
        Task {
            await runAction("Prepare swap and deposit") {
                let walletAddress = try requireWalletAddress()
                let swap = try await prepareSwapPOLToUSDC(
                    walletAddress: walletAddress,
                    polAmount: earnPOLAmount
                )
                let market = try await findPolygonUSDCEarnMarket()
                let depositAmount = (try? formatUnits(value: swap.outputRaw, decimals: 6)) ?? swap.outputDisplay
                preparedEarn = PreparedSwapAndEarnPlan(
                    swap: swap,
                    market: market,
                    depositAmount: depositAmount
                )
                earnStatus = "Swap and Deposit status: prepared API-only two-step plan for about \(swap.outputDisplay)."
            } onFailure: { [self] error in
                earnStatus = "Swap and Deposit status: \(describe(error))"
            }
        }
    }

    func sendSwap() {
        Task {
            await runAction("Send swap") {
                guard let preparedSwap else {
                    throw TrailsDemoError.missingPreparedTransaction
                }

                let initialBalances = balances
                let initialPositions = earnPositions
                selectedFeeOption = nil
                clearFeeOptions()
                defer {
                    selectedFeeOption = nil
                    clearFeeOptions()
                }

                swapStatus = "Swap status: sending..."
                let response = try await sendPreparedSwap(preparedSwap) { response in
                    lastSwapTransaction = TransactionResultViewState(response)
                }
                let result = TransactionResultViewState(response)
                lastSwapTransaction = result
                let selectedFee = preparedSwap.executionState.selectedFeeOption ?? selectedFeeOption
                swapStatus = "Swap status: sent \(shortHash(result.value)). Refreshing balances..."
                await waitForPostSendRefresh(
                    initialBalances: initialBalances,
                    initialEarnPositions: initialPositions,
                    expectation: preparedSwap.postSendExpectation,
                    selectedFeeOption: selectedFee,
                    setStatus: { swapStatus = $0 },
                    pendingStatus: "Swap status: sent \(shortHash(result.value)). Waiting for expected USDC balance",
                    successStatus: "Swap status: sent \(shortHash(result.value)). USDC balance updated.",
                    staleStatus: "Swap status: sent \(shortHash(result.value)). USDC balance has not reached the expected swap output yet."
                )
            } onFailure: { [self] error in
                swapStatus = "Swap status: \(describe(error))"
            }
        }
    }

    func sendDeposit() {
        Task {
            await runAction("Send deposit") {
                guard let preparedDeposit else {
                    throw TrailsDemoError.missingPreparedTransaction
                }

                let initialBalances = balances
                let initialPositions = earnPositions
                selectedFeeOption = nil
                clearFeeOptions()
                defer {
                    selectedFeeOption = nil
                    clearFeeOptions()
                }

                let lastResult = try await sendPreparedYieldTransactions(
                    preparedDeposit,
                    statusPrefix: "Deposit status",
                    label: transactionLabel,
                    setStatus: { depositStatus = $0 },
                    onResult: { lastDepositTransaction = $0 }
                )

                depositStatus = "Deposit status: sent \(shortHash(lastResult.value)). Refreshing balances and earn positions..."
                await waitForPostSendRefresh(
                    initialBalances: initialBalances,
                    initialEarnPositions: initialPositions,
                    expectation: preparedDeposit.postSendExpectation,
                    setStatus: { depositStatus = $0 },
                    pendingStatus: "Deposit status: sent \(shortHash(lastResult.value)). Waiting for earn position update",
                    successStatus: "Deposit status: sent \(shortHash(lastResult.value)). Earn position updated.",
                    staleStatus: "Deposit status: sent \(shortHash(lastResult.value)). Earn position has not updated yet."
                )
            } onFailure: { [self] error in
                depositStatus = "Deposit status: \(describe(error))"
            }
        }
    }

    func sendEarn() {
        Task {
            await runAction("Send swap and deposit") {
                guard let preparedEarn else {
                    throw TrailsDemoError.missingPreparedTransaction
                }

                let initialBalances = balances
                let initialPositions = earnPositions
                selectedFeeOption = nil
                clearFeeOptions()
                defer {
                    selectedFeeOption = nil
                    clearFeeOptions()
                }

                earnStatus = "Swap and Deposit status: sending swap step..."
                let swapResponse = try await sendPreparedSwap(preparedEarn.swap) { response in
                    lastEarnTransaction = TransactionResultViewState(response)
                }
                let swapResult = TransactionResultViewState(swapResponse)
                lastEarnTransaction = swapResult
                let selectedFee = preparedEarn.swap.executionState.selectedFeeOption ?? selectedFeeOption

                await waitForPostSendRefresh(
                    initialBalances: initialBalances,
                    initialEarnPositions: initialPositions,
                    expectation: preparedEarn.swap.postSendExpectation,
                    selectedFeeOption: selectedFee,
                    setStatus: { earnStatus = $0 },
                    pendingStatus: "Swap and Deposit status: sent \(shortHash(swapResult.value)). Waiting for USDC output",
                    successStatus: "Swap and Deposit status: USDC output detected. Preparing deposit step...",
                    staleStatus: "Swap and Deposit status: USDC output has not appeared yet."
                )

                let deposit: PreparedYieldTransactions
                if let preparedDeposit = preparedEarn.executionState.preparedDeposit {
                    deposit = preparedDeposit
                    appendLog("Resuming prepared earn deposit transactions.")
                } else {
                    deposit = try await prepareDepositUSDC(
                        walletAddress: requireWalletAddress(),
                        usdcAmount: preparedEarn.depositAmount,
                        preferredMarket: preparedEarn.market
                    )
                    preparedEarn.executionState.preparedDeposit = deposit
                }

                let lastDepositResult = try await sendPreparedYieldTransactions(
                    deposit,
                    statusPrefix: "Swap and Deposit status",
                    label: depositTransactionLabel,
                    setStatus: { earnStatus = $0 },
                    onResult: { lastEarnTransaction = $0 }
                )

                await waitForPostSendRefresh(
                    initialBalances: initialBalances,
                    initialEarnPositions: initialPositions,
                    expectation: deposit.postSendExpectation,
                    setStatus: { earnStatus = $0 },
                    pendingStatus: "Swap and Deposit status: sent \(shortHash(lastDepositResult.value)). Waiting for earn position update",
                    successStatus: "Swap and Deposit status: sent \(shortHash(lastDepositResult.value)). Earn position updated.",
                    staleStatus: "Swap and Deposit status: sent \(shortHash(lastDepositResult.value)). Earn position has not updated yet."
                )
            } onFailure: { [self] error in
                earnStatus = "Swap and Deposit status: \(describe(error))"
            }
        }
    }

    func withdrawEarnPosition(_ position: EarnPosition) {
        Task {
            await runAction("Withdraw \(position.marketName)") {
                guard position.canWithdraw else {
                    throw TrailsDemoError(message: "This earn position is not currently withdrawable.")
                }

                let initialBalances = balances
                let initialPositions = earnPositions
                selectedFeeOption = nil
                clearFeeOptions()
                withdrawStatuses[position.id] = "Withdraw status: preparing \(position.marketName)..."
                earnPositionsStatus = "Withdraw status: preparing \(position.marketName)..."
                lastWithdrawTransactions[position.id] = nil
                defer {
                    selectedFeeOption = nil
                    clearFeeOptions()
                }

                let prepared: PreparedYieldTransactions
                if let preparedWithdraw = preparedWithdraws[position.id] {
                    prepared = preparedWithdraw
                    appendLog("Resuming withdraw for \(position.marketName).")
                } else {
                    prepared = try await prepareWithdrawEarnPosition(
                        walletAddress: requireWalletAddress(),
                        position: position
                    )
                    preparedWithdraws[position.id] = prepared
                }

                let lastResult = try await sendPreparedYieldTransactions(
                    prepared,
                    statusPrefix: "Withdraw status",
                    label: transactionLabel,
                    setStatus: { status in
                        withdrawStatuses[position.id] = status
                        earnPositionsStatus = status
                    },
                    onResult: { lastWithdrawTransactions[position.id] = $0 }
                )

                await waitForPostSendRefresh(
                    initialBalances: initialBalances,
                    initialEarnPositions: initialPositions,
                    expectation: prepared.postSendExpectation,
                    setStatus: { status in
                        withdrawStatuses[position.id] = status
                        earnPositionsStatus = status
                    },
                    pendingStatus: "Withdraw status: sent \(shortHash(lastResult.value)). Waiting for earn position update",
                    successStatus: "Withdraw status: sent \(shortHash(lastResult.value)). Earn position updated.",
                    staleStatus: "Withdraw status: sent \(shortHash(lastResult.value)). Earn position has not updated yet."
                )
            } onFailure: { [self] error in
                withdrawStatuses[position.id] = "Withdraw status: \(describe(error))"
                earnPositionsStatus = "Withdraw status: \(describe(error))"
            }
        }
    }

    func selectFeeOption(_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection? {
        guard !options.isEmpty else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            feeOptionSelectionRequest?.cancel()
            feeOptionSelectionRequest = FeeOptionSelectionRequest(
                options: options,
                continuation: continuation
            )
            appendLog("Choose a fee token to continue.")
        }
    }

    func chooseFeeOption(_ option: FeeOptionWithBalance) {
        guard hasEnoughBalance(option) else {
            appendLog("! Insufficient \(feeTokenLabel(option)) balance for fee.")
            return
        }

        selectedFeeOption = option
        feeOptionSelectionRequest?.select(option)
        feeOptionSelectionRequest = nil
        appendLog("Selected \(feeTokenLabel(option)).")
    }

    func cancelFeeOptionSelection() {
        selectedFeeOption = nil
        cancelFeeSelection(message: "Fee option selection cancelled")
    }

    func clearPreparedState() {
        cancelFeeSelection(message: "Transaction state cleared")
        preparedSwap = nil
        preparedDeposit = nil
        preparedEarn = nil
        lastSwapTransaction = nil
        lastDepositTransaction = nil
        lastEarnTransaction = nil
        lastWithdrawTransactions = [:]
        withdrawStatuses = [:]
        preparedWithdraws = [:]
        swapStatus = ""
        depositStatus = ""
        earnStatus = ""
    }

    private func runAction(
        _ label: String,
        operation: () async throws -> Void,
        onFailure: ((Error) -> Void)? = nil
    ) async {
        appendLog("> \(label)")
        loadingAction = label
        defer { loadingAction = nil }

        do {
            try await operation()
        } catch is CancellationError {
            appendLog("! \(label) cancelled.")
        } catch {
            onFailure?(error)
            present(error)
            appendLog("! \(describe(error))")
        }
    }

    private func handleAuthCompletion(_ result: TrailsCompleteAuthResult, status: String) async {
        switch result {
        case .walletSelected:
            pendingWalletSelection = nil
            authStatus = status
            redirectStatus = ""
            await refreshSession()
            appendLog("Wallet ready: \(walletAddress ?? "")")
            if let walletAddress {
                await refreshBalances(walletAddress: walletAddress)
                await refreshEarnPositions(walletAddress: walletAddress)
            }
        case .walletSelection(let pendingSelection):
            pendingWalletSelection = pendingSelection
            authStatus = "Choose a wallet to continue."
            redirectStatus = ""
        }
    }

    private func handleWalletActivation(_ result: WalletActivationResult, status: String) async {
        pendingWalletSelection = nil
        authStatus = status
        redirectStatus = ""
        await refreshSession()
        appendLog("Wallet ready: \(result.walletAddress)")
        await refreshBalances(walletAddress: result.walletAddress)
        await refreshEarnPositions(walletAddress: result.walletAddress)
    }

    @discardableResult
    private func refreshSignedInData(status: String = "Refreshing Polygon data...") async -> SignedInDataRefresh {
        guard let walletAddress else {
            return SignedInDataRefresh(balances: nil, positions: nil)
        }

        async let nextBalances = refreshBalances(walletAddress: walletAddress, status: status)
        async let nextPositions = refreshEarnPositions(walletAddress: walletAddress, status: "Refreshing Polygon earn positions...")
        return await SignedInDataRefresh(balances: nextBalances, positions: nextPositions)
    }

    @discardableResult
    private func refreshBalances(
        walletAddress: String,
        status: String = "Loading Polygon balances..."
    ) async -> BalanceState? {
        balances = BalanceState(
            pol: balances.pol,
            usdc: balances.usdc,
            polRaw: balances.polRaw,
            usdcRaw: balances.usdcRaw,
            status: status
        )

        do {
            let pol = try await oms.getNativeTokenBalance(
                network: polygonNetwork,
                walletAddress: walletAddress
            )
            let usdc = try await oms.getTokenBalances(
                network: polygonNetwork,
                contractAddress: polygonUSDC,
                walletAddress: walletAddress,
                includeMetadata: false
            )

            let polRaw = pol?.balance ?? "0"
            let usdcRaw = usdc.balances.first?.balance ?? "0"
            let next = BalanceState(
                pol: formatTokenAmount(polRaw, decimals: 18, symbol: "POL"),
                usdc: formatTokenAmount(usdcRaw, decimals: 6, symbol: "USDC"),
                polRaw: polRaw,
                usdcRaw: usdcRaw,
                status: ""
            )
            balances = next
            return next
        } catch {
            let message = "Balance status: \(describe(error))"
            balances = BalanceState(
                pol: balances.pol,
                usdc: balances.usdc,
                polRaw: balances.polRaw,
                usdcRaw: balances.usdcRaw,
                status: message
            )
            appendLog("! \(message)")
            return nil
        }
    }

    @discardableResult
    private func refreshEarnPositions(
        walletAddress: String,
        status: String = "Loading Polygon earn positions..."
    ) async -> [EarnPosition]? {
        earnPositionsStatus = status

        do {
            async let balancesResult = trailsClient.yieldGetAggregateBalances(
                GetYieldAggregateBalancesRequest(
                    queries: [
                        YieldBalanceQuery(address: walletAddress, network: "polygon")
                    ]
                )
            )
            async let marketsResult = trailsClient.yieldGetMarkets(
                GetYieldMarketsRequest(chainId: "\(polygonChainID)", limit: 100)
            )

            let (balances, markets) = try await (balancesResult, marketsResult)
            let marketsByID = Dictionary(uniqueKeysWithValues: markets.items.map { ($0.id, $0) })
            let positions = balances.items.compactMap { balances -> EarnPosition? in
                guard let balance = primaryEarnBalance(balances) else { return nil }
                let market = marketsByID[balances.yieldId]
                return EarnPosition(
                    id: balances.yieldId,
                    marketID: balances.yieldId,
                    marketName: market?.metadata.name ?? balance.shareToken?.name ?? "\(balance.token.symbol) position",
                    provider: market?.providerId ?? balance.shareToken?.symbol ?? balances.yieldId,
                    amount: balance.amount,
                    amountDisplay: formatDisplayAmount(balance.amount),
                    amountRaw: balance.amountRaw,
                    amountUSD: formatUSD(balance.amountUsd),
                    apy: formatAPY(balances.rewardRate ?? market?.rewardRate),
                    tokenSymbol: balance.token.symbol,
                    outputToken: balance.token.address ?? balance.token.symbol,
                    outputTokenNetwork: balance.token.network,
                    canWithdraw: market?.status.exit ?? true
                )
            }
            .sorted { left, right in
                earnPositionSortValue(left) > earnPositionSortValue(right)
            }

            earnPositions = positions
            if balances.errors.isEmpty {
                earnPositionsStatus = positions.isEmpty ? noEarnPositionsStatus : "Earn positions updated."
            } else {
                earnPositionsStatus = "Earn positions loaded with \(balances.errors.count) API error(s)."
                balances.errors.forEach { appendLog("! Earn balance error: \($0.yieldId): \($0.error)") }
            }
            return positions
        } catch {
            let message = "Earn positions status: \(describe(error))"
            earnPositionsStatus = message
            appendLog("! \(message)")
            return nil
        }
    }

    private func prepareSwapPOLToUSDC(
        walletAddress: String,
        polAmount: String
    ) async throws -> PreparedSwapTransaction {
        let amountRaw = try parsePositiveAmount(polAmount, decimals: 18, label: "POL")
        let response = try await trailsIntentClient.quoteIntent(
            QuoteIntentRequest(
                ownerAddress: walletAddress,
                originChainId: UInt64(polygonChainID),
                originTokenAddress: polygonNativeTokenAddress,
                destinationChainId: UInt64(polygonChainID),
                destinationTokenAddress: polygonUSDC,
                destinationToAddress: walletAddress,
                originTokenAmount: amountRaw,
                tradeType: .exactInput,
                fundMethod: .wallet,
                mode: .swap,
                options: QuoteIntentRequestOptions(swapProvider: .auto)
            )
        )

        let deposit = response.depositTransaction
        guard deposit.chainID == UInt64(polygonChainID) else {
            throw TrailsDemoError.unsupportedYieldTransaction
        }

        let outputRaw = response.outputRaw
        let outputDisplay = formatTokenAmount(outputRaw, decimals: 6, symbol: "USDC")
        return PreparedSwapTransaction(
            title: "Swap POL to USDC",
            request: SendTransactionRequest(to: deposit.to, value: deposit.value, data: deposit.data),
            intent: response.intent,
            outputRaw: outputRaw,
            outputDisplay: outputDisplay,
            postSendExpectation: .usdcIncrease(minIncreaseRaw: outputRaw),
            marketName: nil,
            marketID: nil
        )
    }

    private func prepareDepositUSDC(
        walletAddress: String,
        usdcAmount: String,
        preferredMarket: YieldMarket? = nil
    ) async throws -> PreparedYieldTransactions {
        _ = try parsePositiveAmount(usdcAmount, decimals: 6, label: "USDC")
        let amount = try requireNormalizedAmountInput(usdcAmount, label: "USDC")
        let market: YieldMarket
        if let preferredMarket {
            market = preferredMarket
        } else {
            market = try await findPolygonUSDCEarnMarket()
        }
        let inputToken = market.inputTokens.first ?? market.token
        let response = try await trailsClient.yieldCreateEnterAction(
            CreateYieldActionRequest(
                earnMarketId: market.id,
                userWalletAddress: walletAddress,
                args: YieldActionArguments(
                    amount: amount,
                    inputToken: inputToken.address ?? inputToken.symbol,
                    inputTokenNetwork: inputToken.network,
                    receiverAddress: walletAddress
                )
            )
        )
        let transactions = try parseYieldTransactions(response.action.transactions, label: "Deposit")
        return PreparedYieldTransactions(
            title: "Deposit USDC using Earn",
            transactions: transactions,
            postSendExpectation: .earnMarketIncrease(marketID: market.id),
            marketName: market.metadata.name,
            marketID: market.id
        )
    }

    private func prepareWithdrawEarnPosition(
        walletAddress: String,
        position: EarnPosition
    ) async throws -> PreparedYieldTransactions {
        let response = try await trailsClient.yieldCreateExitAction(
            CreateYieldActionRequest(
                earnMarketId: position.marketID,
                userWalletAddress: walletAddress,
                args: YieldActionArguments(
                    amount: position.amount,
                    outputToken: position.outputToken,
                    outputTokenNetwork: position.outputTokenNetwork
                )
            )
        )
        let transactions = try parseYieldTransactions(response.action.transactions, label: "Withdraw")
        return PreparedYieldTransactions(
            title: "Withdraw \(position.marketName)",
            transactions: transactions,
            postSendExpectation: .earnMarketDecrease(marketID: position.marketID),
            marketName: position.marketName,
            marketID: position.marketID
        )
    }

    private func findPolygonUSDCEarnMarket() async throws -> YieldMarket {
        let response = try await trailsClient.yieldGetMarkets(
            GetYieldMarketsRequest(
                chainId: "\(polygonChainID)",
                search: "USDC",
                limit: 50
            )
        )

        let candidates = response.items
            .filter { $0.status.enter }
            .filter(isUSDCMarket)
            .filter { reasonableAPYRate($0.rewardRate) != nil }
            .sorted {
                (reasonableAPYRate($0.rewardRate) ?? 0) > (reasonableAPYRate($1.rewardRate) ?? 0)
            }

        guard let market = candidates.first else {
            throw TrailsDemoError(message: "No enterable Polygon USDC earn market was returned.")
        }
        return market
    }

    private func parseYieldTransactions(
        _ transactions: [YieldTransaction],
        label: String
    ) throws -> [ParsedYieldTransaction] {
        let parsed = try transactions
            .filter { $0.isMessage != true }
            .map { try parseUnsignedYieldTransaction($0.unsignedTransaction) }

        guard !parsed.isEmpty else {
            throw TrailsDemoError(message: "\(label) action did not return a transaction.")
        }

        if parsed.contains(where: { $0.chainID != polygonChainID }) {
            throw TrailsDemoError(message: "\(label) returned a non-Polygon transaction, but this demo only sends Polygon transactions.")
        }

        return parsed
    }

    private func sendPreparedSwap(
        _ prepared: PreparedSwapTransaction,
        onWalletSent: (SendTransactionResponse) -> Void
    ) async throws -> SendTransactionResponse {
        let state = prepared.executionState
        var response: SendTransactionResponse

        if let submittedResponse = state.submittedResponse {
            response = submittedResponse
            appendLog("Resuming Trails intent for sent swap \(shortHash(response.txnHash ?? response.txnId)).")
        } else {
            response = try await oms.sendTransaction(
                network: polygonNetwork,
                request: prepared.request,
                selectFeeOption: .custom { options in
                    try await self.selectFeeOption(options)
                }
            )
            state.submittedResponse = response
            state.selectedFeeOption = selectedFeeOption
        }

        onWalletSent(response)
        response = try await waitForTransactionHash(response)
        state.submittedResponse = response
        onWalletSent(response)

        if state.committedIntentID == nil {
            state.committedIntentID = try await trailsIntentClient.commitIntent(prepared.intent)
        }

        guard let intentID = state.committedIntentID else {
            throw TrailsDemoError(message: "Trails commit did not return an intent id.")
        }
        guard let transactionHash = nonEmptyString(response.txnHash) else {
            throw TrailsDemoError(message: "Wallet transaction hash was not available yet. Try sending again in a few seconds.")
        }

        if !state.didExecuteIntent {
            try await trailsIntentClient.executeIntent(
                intentID: intentID,
                depositTransactionHash: transactionHash
            )
            state.didExecuteIntent = true
        }

        return response
    }

    private func waitForTransactionHash(_ response: SendTransactionResponse) async throws -> SendTransactionResponse {
        if nonEmptyString(response.txnHash) != nil {
            return response
        }

        appendLog("Waiting for chain hash for \(shortHash(response.txnId)).")
        var latest = response
        for attempt in 1...postSendRefreshAttempts {
            let status = try await oms.getTransactionStatus(txnId: response.txnId)
            latest = SendTransactionResponse(
                txnId: response.txnId,
                status: status.status,
                txnHash: status.txnHash
            )

            if let transactionHash = nonEmptyString(latest.txnHash) {
                appendLog("Chain hash ready: \(shortHash(transactionHash)).")
                return latest
            }

            if case .unknown(let status) = status.status {
                throw TrailsDemoError(message: "Wallet transaction returned unsupported status \(status).")
            }

            if attempt < postSendRefreshAttempts {
                try await Task.sleep(nanoseconds: postSendRefreshDelayNanoseconds)
            }
        }

        appendLog("! Chain hash did not appear for \(shortHash(latest.txnId)).")
        throw TrailsDemoError(message: "Wallet transaction hash was not available yet. Try sending again in a few seconds.")
    }

    private func sendYieldTransaction(_ transaction: ParsedYieldTransaction) async throws -> SendTransactionResponse {
        try await oms.sendTransaction(
            network: polygonNetwork,
            request: transaction.request,
            selectFeeOption: .custom { options in
                try await self.selectFeeOption(options)
            }
        )
    }

    private func sendPreparedYieldTransactions(
        _ prepared: PreparedYieldTransactions,
        statusPrefix: String,
        label: (_ index: Int, _ total: Int) -> String,
        setStatus: (String) -> Void,
        onResult: (TransactionResultViewState) -> Void
    ) async throws -> TransactionResultViewState {
        var lastResult: TransactionResultViewState?

        for (index, transaction) in prepared.transactions.enumerated() {
            let transactionLabel = label(index, prepared.transactions.count)

            if let submittedResponse = prepared.executionState.submittedResponse(at: index) {
                let result = TransactionResultViewState(submittedResponse)
                lastResult = result
                onResult(result)
                setStatus("\(statusPrefix): already sent \(transactionLabel) \(shortHash(result.value)).")
                continue
            }

            setStatus("\(statusPrefix): sending \(transactionLabel)...")
            let response = try await sendYieldTransaction(transaction)
            prepared.executionState.recordSubmittedResponse(response, at: index)

            let result = TransactionResultViewState(response)
            lastResult = result
            onResult(result)
            setStatus("\(statusPrefix): sent \(transactionLabel) \(shortHash(result.value)).")
        }

        guard let lastResult else {
            throw TrailsDemoError.missingYieldTransaction
        }

        return lastResult
    }

    private func waitForPostSendRefresh(
        initialBalances: BalanceState,
        initialEarnPositions: [EarnPosition],
        expectation: PostSendExpectation,
        selectedFeeOption: FeeOptionWithBalance? = nil,
        setStatus: (String) -> Void,
        pendingStatus: String,
        successStatus: String,
        staleStatus: String
    ) async {
        for attempt in 1...postSendRefreshAttempts {
            let suffix = attempt == 1 ? "..." : " (\(attempt)/\(postSendRefreshAttempts))..."
            setStatus("\(pendingStatus)\(suffix)")
            let refreshed = await refreshSignedInData()

            if hasPostSendDataUpdate(
                initialBalances: initialBalances,
                initialEarnPositions: initialEarnPositions,
                expectation: expectation,
                selectedFeeOption: selectedFeeOption,
                refreshed: refreshed
            ) {
                setStatus(successStatus)
                return
            }

            if attempt < postSendRefreshAttempts {
                try? await Task.sleep(nanoseconds: postSendRefreshDelayNanoseconds)
            }
        }

        setStatus("\(staleStatus) Use Refresh to check again.")
    }

    private func hasPostSendDataUpdate(
        initialBalances: BalanceState,
        initialEarnPositions: [EarnPosition],
        expectation: PostSendExpectation,
        selectedFeeOption: FeeOptionWithBalance?,
        refreshed: SignedInDataRefresh
    ) -> Bool {
        switch expectation {
        case .usdcIncrease(let minIncreaseRaw):
            guard let refreshedBalances = refreshed.balances else { return false }
            let feeRaw = selectedFeeOption.map(usdcFeeRaw) ?? "0"
            let expectedIncrease = subtractUnsignedIntegers(minIncreaseRaw, feeRaw) ?? "0"
            if expectedIncrease == "0" {
                return compareUnsignedInteger(refreshedBalances.usdcRaw, initialBalances.usdcRaw) != .orderedSame
            }
            let target = addUnsignedIntegers(initialBalances.usdcRaw, expectedIncrease)
            return compareUnsignedInteger(refreshedBalances.usdcRaw, target).map { $0 != .orderedAscending } ?? false
        case .earnMarketIncrease(let marketID):
            guard let refreshedPositions = refreshed.positions else { return false }
            let previous = findEarnPosition(initialEarnPositions, marketID: marketID)
            guard let next = findEarnPosition(refreshedPositions, marketID: marketID) else { return false }
            let previousAmount = previous?.amountRaw ?? "0"
            return compareUnsignedInteger(next.amountRaw, previousAmount) == .orderedDescending
        case .earnMarketDecrease(let marketID):
            guard let refreshedPositions = refreshed.positions else { return false }
            guard let previous = findEarnPosition(initialEarnPositions, marketID: marketID) else { return false }
            guard let next = findEarnPosition(refreshedPositions, marketID: marketID) else { return true }
            return compareUnsignedInteger(next.amountRaw, previous.amountRaw) == .orderedAscending
        }
    }

    private func requireWalletAddress() throws -> String {
        guard let walletAddress, walletAddress.hasPrefix("0x") else {
            throw TrailsDemoError.missingWallet
        }
        return walletAddress
    }

    private func present(_ error: Error) {
        self.error = AppError(error)
    }

    private func describe(_ error: Error) -> String {
        AppError(error).message
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
    }

    private func clearFeeOptions() {
        feeOptionSelectionRequest = nil
    }

    private func cancelFeeSelection(message: String) {
        feeOptionSelectionRequest?.cancel()
        feeOptionSelectionRequest = nil
        selectedFeeOption = nil
        appendLog("! \(message)")
    }
}

private func primaryEarnBalance(_ balances: YieldBalances) -> YieldBalance? {
    if let outputTokenBalance = balances.outputTokenBalance,
       hasPositiveEarnBalance(outputTokenBalance) {
        return outputTokenBalance
    }

    return balances.balances.first(where: hasPositiveEarnBalance)
}

private func hasPositiveEarnBalance(_ balance: YieldBalance) -> Bool {
    compareUnsignedInteger(balance.amountRaw, "0") == .orderedDescending
}

private func earnPositionSortValue(_ position: EarnPosition) -> Double {
    if let amountUSD = position.amountUSD,
       let value = Double(amountUSD.filter { $0.isNumber || $0 == "." }),
       value.isFinite {
        return value
    }

    return Double(position.amount) ?? 0
}

private func findEarnPosition(_ positions: [EarnPosition], marketID: String) -> EarnPosition? {
    positions.first { $0.marketID == marketID || $0.id == marketID }
}

private func isUSDCMarket(_ market: YieldMarket) -> Bool {
    let input = market.inputTokens.first ?? market.token
    return input.address?.lowercased() == polygonUSDC.lowercased()
}

private func reasonableAPYRate(_ rewardRate: YieldRewardRate) -> Double? {
    let total = rewardRate.total
    guard total.isFinite, total >= 0, total <= 0.5 else {
        return nil
    }
    return total
}

private func usdcFeeRaw(_ option: FeeOptionWithBalance) -> String {
    feeTokenLabel(option).uppercased() == "USDC" ? option.feeOption.value : "0"
}

private func nonEmptyString(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func transactionLabel(index: Int, total: Int) -> String {
    total == 1 ? "transaction" : "transaction \(index + 1)/\(total)"
}

private func depositTransactionLabel(index: Int, total: Int) -> String {
    total == 1 ? "deposit transaction" : "deposit transaction \(index + 1)/\(total)"
}
