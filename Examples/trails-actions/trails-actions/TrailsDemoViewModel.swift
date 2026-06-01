import Combine
import Foundation
@preconcurrency import OMS_SDK

@MainActor
final class TrailsDemoViewModel: ObservableObject {
    @Published var session = SessionState(walletAddress: nil)
    @Published var authStep: AuthStep = .email
    @Published var email = ""
    @Published var code = ""
    @Published var pendingWalletSelection: PendingWalletSelection?
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

    let oms = OMSClient(
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
    private let manualWalletSelectionKey = "oms-trails-actions-manual-wallet-selection"

    init() {
        self.useManualWalletSelection = UserDefaults.standard.bool(forKey: manualWalletSelectionKey)
        self.session = oms.wallet.session
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

    func refreshSession() {
        session = oms.wallet.session
    }

    func refreshAfterLaunch() async {
        refreshSession()
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
                try await oms.wallet.startEmailAuth(email: normalizedEmail)
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
                let result = try await oms.wallet.completeEmailAuth(
                    code: normalizedCode,
                    walletSelection: walletSelectionBehavior
                )
                code = ""
                authStep = .email
                handleAuthCompletion(result, status: "Email login complete.")
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
                let started = try await oms.wallet.startOidcRedirectAuth(
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
            let result = try await oms.wallet.handleOidcRedirectCallback(
                url.absoluteString,
                walletSelection: walletSelectionBehavior
            )

            switch result {
            case .completed:
                safariAuthSession = nil
                pendingWalletSelection = nil
                redirectStatus = "Google login complete."
                refreshSession()
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
                handleWalletActivation(result, status: "Wallet selected.")
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
                handleWalletActivation(result, status: "Wallet created.")
            } onFailure: { [self] error in
                authStatus = "Wallet creation error: \(describe(error))"
            }
        }
    }

    func cancelPendingWalletSelection() {
        Task {
            await runAction("Cancel wallet selection") {
                try oms.wallet.signOut()
                pendingWalletSelection = nil
                authStep = .email
                code = ""
                authStatus = "Enter an email to start."
                redirectStatus = ""
                clearPreparedState()
                refreshSession()
            }
        }
    }

    func signOut() {
        Task {
            await runAction("Sign out") {
                try oms.wallet.signOut()
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
                refreshSession()
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
        cancelFeeSelection(message: "Amount changed")
        swapPOLAmount = normalizeAmountInput(value)
        preparedSwap = nil
        lastSwapTransaction = nil
        swapStatus = ""
    }

    func updateDepositUSDCAmount(_ value: String) {
        cancelFeeSelection(message: "Amount changed")
        depositUSDCAmount = normalizeAmountInput(value)
        preparedDeposit = nil
        lastDepositTransaction = nil
        depositStatus = ""
    }

    func updateEarnPOLAmount(_ value: String) {
        cancelFeeSelection(message: "Amount changed")
        earnPOLAmount = normalizeAmountInput(value)
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

                var lastResult: TransactionResultViewState?
                for (index, transaction) in preparedDeposit.transactions.enumerated() {
                    let label = preparedDeposit.transactions.count == 1
                        ? "transaction"
                        : "transaction \(index + 1)/\(preparedDeposit.transactions.count)"
                    depositStatus = "Deposit status: sending \(label)..."
                    let response = try await sendYieldTransaction(transaction)
                    lastResult = TransactionResultViewState(response)
                    lastDepositTransaction = lastResult
                    depositStatus = "Deposit status: sent \(label) \(shortHash(lastResult?.value ?? ""))."
                }

                guard let lastResult else {
                    throw TrailsDemoError.missingYieldTransaction
                }

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

                let deposit = try await prepareDepositUSDC(
                    walletAddress: requireWalletAddress(),
                    usdcAmount: preparedEarn.depositAmount,
                    preferredMarket: preparedEarn.market
                )

                var lastDepositResult: TransactionResultViewState?
                for (index, transaction) in deposit.transactions.enumerated() {
                    let label = deposit.transactions.count == 1
                        ? "deposit transaction"
                        : "deposit transaction \(index + 1)/\(deposit.transactions.count)"
                    earnStatus = "Swap and Deposit status: sending \(label)..."
                    let response = try await sendYieldTransaction(transaction)
                    lastDepositResult = TransactionResultViewState(response)
                    lastEarnTransaction = lastDepositResult
                }

                guard let lastDepositResult else {
                    throw TrailsDemoError.missingYieldTransaction
                }

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

                let prepared = try await prepareWithdrawEarnPosition(
                    walletAddress: requireWalletAddress(),
                    position: position
                )
                var lastResult: TransactionResultViewState?

                for (index, transaction) in prepared.transactions.enumerated() {
                    let label = prepared.transactions.count == 1
                        ? "transaction"
                        : "transaction \(index + 1)/\(prepared.transactions.count)"
                    withdrawStatuses[position.id] = "Withdraw status: sending \(label)..."
                    earnPositionsStatus = "Withdraw status: sending \(label)..."
                    let response = try await sendYieldTransaction(transaction)
                    let result = TransactionResultViewState(response)
                    lastResult = result
                    lastWithdrawTransactions[position.id] = result
                    withdrawStatuses[position.id] = "Withdraw status: sent \(label) \(shortHash(result.value))."
                    earnPositionsStatus = "Withdraw status: sent \(label) \(shortHash(result.value))."
                }

                guard let lastResult else {
                    throw TrailsDemoError.missingYieldTransaction
                }

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

    private func handleAuthCompletion(_ result: CompleteAuthResult, status: String) {
        switch result {
        case .walletSelected:
            pendingWalletSelection = nil
            authStatus = status
            redirectStatus = ""
            refreshSession()
            appendLog("Wallet ready: \(walletAddress ?? "")")
            if let walletAddress {
                Task {
                    await refreshBalances(walletAddress: walletAddress)
                    await refreshEarnPositions(walletAddress: walletAddress)
                }
            }
        case .walletSelection(let pendingSelection):
            pendingWalletSelection = pendingSelection
            authStatus = "Choose a wallet to continue."
            redirectStatus = ""
        }
    }

    private func handleWalletActivation(_ result: WalletActivationResult, status: String) {
        pendingWalletSelection = nil
        authStatus = status
        redirectStatus = ""
        refreshSession()
        appendLog("Wallet ready: \(result.walletAddress)")
        Task {
            await refreshBalances(walletAddress: result.walletAddress)
            await refreshEarnPositions(walletAddress: result.walletAddress)
        }
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
            let pol = try await oms.indexer.getNativeTokenBalance(
                network: polygonNetwork,
                walletAddress: walletAddress
            )
            let usdc = try await oms.indexer.getTokenBalances(
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
        let amount = normalizeAmountInput(usdcAmount)
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
        let response: SendTransactionResponse

        if let submittedResponse = state.submittedResponse {
            response = submittedResponse
            appendLog("Resuming Trails intent for sent swap \(shortHash(response.txnHash ?? response.txnId)).")
        } else {
            response = try await oms.wallet.sendTransaction(
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

        if state.committedIntentID == nil {
            state.committedIntentID = try await trailsIntentClient.commitIntent(prepared.intent)
        }

        guard let intentID = state.committedIntentID else {
            throw TrailsDemoError(message: "Trails commit did not return an intent id.")
        }

        if !state.didExecuteIntent {
            try await trailsIntentClient.executeIntent(
                intentID: intentID,
                depositTransactionHash: response.txnHash
            )
            state.didExecuteIntent = true
        }

        return response
    }

    private func sendYieldTransaction(_ transaction: ParsedYieldTransaction) async throws -> SendTransactionResponse {
        try await oms.wallet.sendTransaction(
            network: polygonNetwork,
            request: transaction.request,
            selectFeeOption: .custom { options in
                try await self.selectFeeOption(options)
            }
        )
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
