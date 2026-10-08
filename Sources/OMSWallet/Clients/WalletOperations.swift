import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The `Network` for the signing context (e.g. `.mainnet`, `.polygon`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: Network, message: String) async throws -> String {
        try await runOMSWalletOperation(.walletSignMessage) {
            try requireActiveEthereumWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = SignMessageRequest(
                network: network.waasChainId,
                walletId: walletId,
                message: message
            )

            let response = try await signedClient.signMessage(params)
            return response.signature
        }
    }

    public func signSolanaMessage(message: String) async throws -> String {
        try await runOMSWalletOperation(.walletSignSolanaMessage) {
            try requireActiveSolanaWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            return try await signedClient.signMessage(
                SignMessageRequest(network: "", walletId: walletId, message: message)
            ).signature
        }
    }

    public func signTypedData(network: Network, typedData: JSONValue) async throws -> String {
        try await runOMSWalletOperation(.walletSignTypedData) {
            try requireActiveEthereumWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = SignTypedDataRequest(
                network: network.waasChainId,
                walletId: walletId,
                typedData: typedData.waasValue
            )

            let response = try await signedClient.signTypedData(params)
            return response.signature
        }
    }

    public func isValidMessageSignature(
        network: Network,
        walletAddress: String? = nil,
        message: String,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidMessageSignature) {
            let walletAddress = try verificationWalletAddress(walletAddress, walletType: .ethereum)
            let response = try await publicClient.isValidMessageSignature(
                IsValidMessageSignatureRequest(
                    network: network.waasChainId,
                    networkFamily: .evm,
                    walletAddress: walletAddress,
                    message: message,
                    signature: signature
                )
            )

            return response.isValid
        }
    }

    public func isValidSolanaMessageSignature(
        walletAddress: String? = nil,
        message: String,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidSolanaMessageSignature) {
            let walletAddress = try verificationWalletAddress(walletAddress, walletType: .solana)
            let response = try await publicClient.isValidMessageSignature(
                IsValidMessageSignatureRequest(
                    networkFamily: .solana,
                    walletAddress: walletAddress,
                    message: message,
                    signature: signature
                )
            )
            return response.isValid
        }
    }

    public func isValidTypedDataSignature(
        network: Network,
        walletAddress: String? = nil,
        typedData: JSONValue,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidTypedDataSignature) {
            let walletAddress = try verificationWalletAddress(walletAddress, walletType: .ethereum)
            let response = try await publicClient.isValidTypedDataSignature(
                IsValidTypedDataSignatureRequest(
                    network: network.waasChainId,
                    networkFamily: .evm,
                    walletAddress: walletAddress,
                    typedData: typedData.waasValue,
                    signature: signature
                )
            )

            return response.isValid
        }
    }

    public func signTronMessage(message: String) async throws -> String {
        try await runOMSWalletOperation(.walletSignTronMessage) {
            try requireActiveTronWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            return try await signedClient.signMessage(
                SignMessageRequest(network: "", walletId: walletId, message: message)
            ).signature
        }
    }

    public func signTronTypedData(typedData: JSONValue) async throws -> String {
        try await runOMSWalletOperation(.walletSignTronTypedData) {
            try requireActiveTronWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            return try await signedClient.signTypedData(
                SignTypedDataRequest(network: "", walletId: walletId, typedData: typedData.waasValue)
            ).signature
        }
    }

    public func isValidTronMessageSignature(
        walletAddress: String? = nil,
        message: String,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidTronMessageSignature) {
            let walletAddress = try verificationWalletAddress(walletAddress, walletType: .tron)
            return try await publicClient.isValidMessageSignature(
                IsValidMessageSignatureRequest(
                    networkFamily: .tron,
                    walletAddress: walletAddress,
                    message: message,
                    signature: signature
                )
            ).isValid
        }
    }

    public func isValidTronTypedDataSignature(
        walletAddress: String? = nil,
        typedData: JSONValue,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidTronTypedDataSignature) {
            let walletAddress = try verificationWalletAddress(walletAddress, walletType: .tron)
            return try await publicClient.isValidTypedDataSignature(
                IsValidTypedDataSignatureRequest(
                    networkFamily: .tron,
                    walletAddress: walletAddress,
                    typedData: typedData.waasValue,
                    signature: signature
                )
            ).isValid
        }
    }

    public func sendTransaction(
        network: Network,
        to: String,
        value: String,
        selectFeeOption: FeeOptionSelector? = nil,
        mode: TransactionMode = .relayer,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletSendTransaction) {
            try requireActiveEthereumWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            return try await sendTransaction(
                network: network,
                request: SendTransactionRequest(
                    to: to,
                    value: value,
                    data: nil,
                    mode: mode
                ),
                selectFeeOption: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletId: walletId,
                walletAddress: walletAddress
            )
        }
    }

    public func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        selectFeeOption: FeeOptionSelector? = nil,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletSendTransaction) {
            try requireActiveEthereumWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            return try await sendTransaction(
                network: network,
                request: request,
                selectFeeOption: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletId: walletId,
                walletAddress: walletAddress
            )
        }
    }

    public func sendSolanaTransfer(
        network: SolanaNetwork,
        asset: String,
        to: String,
        amount: String,
        selectFeeOption: FeeOptionSelector? = nil,
        mode: TransactionMode = .relayer,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletSendSolanaTransfer) {
            try requireActiveSolanaWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            let prepared = try await signedClient.prepareSolanaTransfer(
                PrepareSolanaTransferRequest(
                    network: network.rawValue,
                    walletId: walletId,
                    asset: asset,
                    recipient: SolanaRecipient(address: to),
                    amount: amount,
                    mode: mode.waasValue
                )
            )
            return try await execute(
                feeBalanceNetwork: .solana(network),
                prepareResponse: prepared,
                feeOptionSelector: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletAddress: walletAddress
            )
        }
    }

    public func sendTronTransaction(
        network: TronNetwork,
        to: String,
        value: String = "0",
        data: String? = nil,
        selectFeeOption: FeeOptionSelector? = nil,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletSendTronTransaction) {
            try requireActiveTronWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            // `data` is forwarded as given: nil omits the field (a TRX transfer), while any value,
            // even "0x", makes this a contract call.
            let prepared = try await signedClient.prepareTronTransaction(
                PrepareTronTransactionRequest(
                    network: network.rawValue,
                    walletId: walletId,
                    to: to,
                    value: value,
                    data: data,
                    mode: TransactionMode.native.waasValue
                )
            )
            return try await execute(
                feeBalanceNetwork: .tron(network),
                prepareResponse: prepared,
                feeOptionSelector: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletAddress: walletAddress
            )
        }
    }

    public func callTronContract(
        network: TronNetwork,
        contractAddress: String,
        method: String,
        args: [AbiArg]? = nil,
        selectFeeOption: FeeOptionSelector? = nil,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletCallTronContract) {
            try requireActiveTronWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            try requireContractMethodName(method)
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            let prepared = try await signedClient.prepareTronContractCall(
                PrepareTronContractCallRequest(
                    network: network.rawValue,
                    walletId: walletId,
                    contract: contractAddress,
                    method: method,
                    args: args?.map { $0.waasValue },
                    mode: TransactionMode.native.waasValue
                )
            )
            return try await execute(
                feeBalanceNetwork: .tron(network),
                prepareResponse: prepared,
                feeOptionSelector: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletAddress: walletAddress
            )
        }
    }

    private func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        selectFeeOption: FeeOptionSelector?,
        waitForStatus: Bool,
        statusPolling: TransactionStatusPollingOptions,
        walletId: String,
        walletAddress: String?
    ) async throws -> SendTransactionResponse {
        let prepareResponse = try await signedClient.prepareEthereumTransaction(
            PrepareEthereumTransactionRequest(
                network: network.waasChainId,
                walletId: walletId,
                to: request.to,
                value: request.value,
                data: request.data,
                mode: request.mode.waasValue
            )
        )

        return try await self.execute(
            feeBalanceNetwork: .ethereum(network),
            prepareResponse: prepareResponse,
            feeOptionSelector: selectFeeOption,
            waitForStatus: waitForStatus,
            statusPolling: statusPolling,
            walletAddress: walletAddress
        )
    }

    public func callContract(
        network: Network,
        contractAddress: String,
        method: String,
        args: [AbiArg]? = nil,
        selectFeeOption: FeeOptionSelector? = nil,
        mode: TransactionMode = .relayer,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletCallContract) {
            try requireActiveEthereumWallet()
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            try requireContractMethodName(method)
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            let prepareResponse = try await signedClient.prepareEthereumContractCall(
                PrepareEthereumContractCallRequest(
                    network: network.waasChainId,
                    walletId: walletId,
                    contract: contractAddress,
                    method: method,
                    args: args?.map { $0.waasValue },
                    mode: mode.waasValue
                )
            )

            return try await self.execute(
                feeBalanceNetwork: .ethereum(network),
                prepareResponse: prepareResponse,
                feeOptionSelector: selectFeeOption,
                waitForStatus: waitForStatus,
                statusPolling: statusPolling,
                walletAddress: walletAddress
            )
        }
    }

    /// Returns the current execution status for a prepared or submitted transaction.
    ///
    /// - Parameter txnId: The transaction ID returned by the wallet API prepare/execute flow.
    /// - Returns: The current transaction status and transaction hash when available.
    public func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse {
        try await runOMSWalletOperation(.walletGetTransactionStatus) {
            _ = try requireActiveWalletId()
            try requireActiveCredential()
            return try await signedClient.transactionStatus(
                TransactionStatusRequest(txnId: txnId)
            ).sdkValue
        }
    }

    private func execute(
        feeBalanceNetwork: FeeBalanceNetwork?,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        waitForStatus: Bool,
        statusPolling: TransactionStatusPollingOptions,
        walletAddress: String?
    ) async throws -> SendTransactionResponse {
        if waitForStatus {
            try validateTransactionStatusPollingOptions(statusPolling)
        }
        let feeOptionSelection = try await selectFeeOption(
            feeBalanceNetwork: feeBalanceNetwork,
            prepareResponse: prepareResponse,
            feeOptionSelector: feeOptionSelector,
            walletAddress: walletAddress
        )

        let executeRequest = ExecuteRequest(
            txnId: prepareResponse.txnId,
            feeOption: feeOptionSelection?.waasValue
        )

        let executeResponse: ExecuteResponse
        do {
            executeResponse = try await signedClient.execute(executeRequest)
        } catch let error as CancellationError {
            throw error
        } catch {
            let sdkError = toOMSWalletError(error, operation: .walletExecute)
            throw OMSWalletError(
                code: .transactionExecutionUnconfirmed,
                message: "Transaction execution failed before status could be confirmed",
                operation: .walletExecute,
                status: sdkError.status,
                txnId: prepareResponse.txnId,
                retryable: false,
                upstreamError: sdkError.upstreamError,
                underlyingError: sdkError
            )
        }
        if !waitForStatus {
            return SendTransactionResponse(
                txnId: prepareResponse.txnId,
                status: executeResponse.status.sdkValue,
                statusResolution: .notRequested
            )
        }

        let statusResult = try await waitForTransactionStatus(
            txnId: prepareResponse.txnId,
            fallbackStatus: executeResponse.status.sdkValue,
            options: statusPolling
        )
        let response = SendTransactionResponse(
            txnId: prepareResponse.txnId,
            status: statusResult.response.status,
            txnHash: statusResult.response.txnHash,
            statusResolution: statusResult.resolution
        )

        if response.statusResolution == .timedOut {
            return response
        }

        if isSubmittedTransactionResult(response) {
            return response
        }

        if response.status == .pending || response.status == .failed {
            return response
        }

        throw TransactionError.transactionFailed(status: response.status)
    }

    private func selectFeeOption(
        feeBalanceNetwork: FeeBalanceNetwork?,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        walletAddress: String?
    ) async throws -> FeeOptionSelection? {
        let feeOptions = prepareResponse.feeOptions.map { $0.sdkValue }
        guard !prepareResponse.sponsored else {
            if let feeOptionSelector {
                _ = try await feeOptionSelector([FeeOptionWithBalance]())
            }
            return nil
        }

        guard !feeOptions.isEmpty else {
            throw TransactionError.noFeeOptionsAvailable
        }

        guard let feeOptionSelector else {
            guard let feeOptionSelection = feeOptions.defaultSelection() else {
                throw TransactionError.noFeeOptionsAvailable
            }
            return feeOptionSelection
        }

        let options: [FeeOptionWithBalance]
        if let feeBalanceNetwork, let walletAddress {
            switch feeBalanceNetwork {
            case .ethereum(let network):
                options = await enrichFeeOptionsWithBalances(
                    network: network,
                    walletAddress: walletAddress,
                    feeOptions: feeOptions
                )
            case .solana(let network):
                options = await enrichSolanaFeeOptionsWithBalances(
                    network: network,
                    walletAddress: walletAddress,
                    feeOptions: feeOptions
                )
            case .tron(let network):
                options = await enrichTronFeeOptionsWithBalances(
                    network: network,
                    walletAddress: walletAddress,
                    feeOptions: feeOptions
                )
            }
        } else {
            options = feeOptions.enumerated().map { index, feeOption in
                FeeOptionWithBalance(
                    feeOption: feeOption,
                    selection: FeeOptionSelection(feeOption: feeOption, index: UInt32(index))
                )
            }
        }
        let feeOptionSelection = try await feeOptionSelector(options)

        guard let feeOptionSelection else {
            throw TransactionError.noFeeOptionSelected
        }

        return feeOptionSelection
    }

    private func enrichFeeOptionsWithBalances(
        network: Network,
        walletAddress: String,
        feeOptions: [FeeOption]
    ) async -> [FeeOptionWithBalance] {
        let contractAddresses = feeOptions
            .compactMap { normalizedAddress($0.token.contractAddress) }
            .reduce(into: [String]()) { addresses, address in
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }

        let balances = try? await indexerClient.getBalances(
            GetBalancesParams(
                walletAddress: walletAddress,
                networks: [network],
                contractAddresses: contractAddresses,
                includeMetadata: false
            )
        )

        let nativeBalance = feeOptions.contains(where: { $0.token.isNativeToken })
            ? balances?.nativeBalances.first { $0.chainId == Int64(network.id) }.map(TokenBalance.native)
            : nil

        var balancesByContract: [String: TokenBalance?] = [:]
        for contractAddress in contractAddresses {
            balancesByContract[contractAddress] = balances?.balances.first {
                    normalizedAddress($0.contractAddress) == contractAddress
                }.map(TokenBalance.contract)
        }

        return feeOptions.enumerated().map { index, feeOption in
            let balance: TokenBalance?
            if feeOption.token.isNativeToken {
                balance = nativeBalance
            } else {
                balance = normalizedAddress(feeOption.token.contractAddress)
                    .flatMap { balancesByContract[$0] ?? nil }
            }

            let decimals = feeOption.token.balanceDecimals
            return FeeOptionWithBalance(
                feeOption: feeOption,
                selection: FeeOptionSelection(feeOption: feeOption, index: UInt32(index)),
                balance: balance,
                available: formatTokenAmount(balance?.balance, decimals: decimals),
                availableRaw: balance?.balance,
                decimals: decimals
            )
        }
    }

    private func enrichSolanaFeeOptionsWithBalances(
        network: SolanaNetwork,
        walletAddress: String,
        feeOptions: [FeeOption]
    ) async -> [FeeOptionWithBalance] {
        let mintAddresses = feeOptions
            .filter { !$0.token.isNativeToken }
            .compactMap { normalizedBase58Address($0.token.contractAddress) }
            .reduce(into: [String]()) { addresses, address in
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }
        let includesNative = feeOptions.contains { $0.token.isNativeToken }
        let balances = try? await indexerClient.getSolanaBalances(
            GetSolanaBalancesParams(
                walletAddress: walletAddress,
                networks: [network],
                includeMetadata: false,
                omitNativeBalances: !includesNative,
                mintAddresses: mintAddresses
            )
        )
        let nativeBalance = balances?.balances.first { balance in
            if case .native(let value) = balance {
                return value.network == network
            }
            return false
        }
        var balancesByMint: [String: SolanaBalance] = [:]
        for balance in balances?.balances ?? [] {
            if case .fungibleToken(let value) = balance, value.network == network {
                balancesByMint[value.mintAddress] = balance
            }
        }

        return feeOptions.enumerated().map { index, feeOption in
            let balance = feeOption.token.isNativeToken
                ? nativeBalance
                : normalizedBase58Address(feeOption.token.contractAddress).flatMap { balancesByMint[$0] }
            let decimals = balance?.decimals ?? feeOption.token.decimals.map(Int.init)
            return FeeOptionWithBalance(
                feeOption: feeOption,
                selection: FeeOptionSelection(feeOption: feeOption, index: UInt32(index)),
                available: formatTokenAmount(balance?.balance, decimals: decimals),
                availableRaw: balance?.balance,
                decimals: decimals
            )
        }
    }

    private func enrichTronFeeOptionsWithBalances(
        network: TronNetwork,
        walletAddress: String,
        feeOptions: [FeeOption]
    ) async -> [FeeOptionWithBalance] {
        let contractAddresses = feeOptions
            .filter { !$0.token.isNativeToken }
            .compactMap { normalizedBase58Address($0.token.contractAddress) }
            .reduce(into: [String]()) { addresses, address in
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }
        let includesNative = feeOptions.contains { $0.token.isNativeToken }
        let balances = try? await indexerClient.getTronBalances(
            GetTronBalancesParams(
                walletAddress: walletAddress,
                networks: [network],
                includeMetadata: false,
                omitNativeBalances: !includesNative,
                contractAddresses: contractAddresses
            )
        )
        let nativeBalance = balances?.balances.first { balance in
            if case .native(let value) = balance {
                return value.network == network
            }
            return false
        }
        var balancesByContract: [String: TronBalance] = [:]
        for balance in balances?.balances ?? [] {
            if case .fungibleToken(let value) = balance, value.network == network {
                balancesByContract[value.contractAddress] = balance
            }
        }

        return feeOptions.enumerated().map { index, feeOption in
            let balance = feeOption.token.isNativeToken
                ? nativeBalance
                : normalizedBase58Address(feeOption.token.contractAddress).flatMap { balancesByContract[$0] }
            let decimals = balance?.decimals ?? feeOption.token.decimals.map(Int.init)
            return FeeOptionWithBalance(
                feeOption: feeOption,
                selection: FeeOptionSelection(feeOption: feeOption, index: UInt32(index)),
                available: formatTokenAmount(balance?.balance, decimals: decimals),
                availableRaw: balance?.balance,
                decimals: decimals
            )
        }
    }

    private func waitForTransactionStatus(
        txnId: String,
        fallbackStatus: TransactionStatus,
        options: TransactionStatusPollingOptions
    ) async throws -> (
        response: TransactionStatusResponse,
        resolution: TransactionStatusResolution
    ) {
        let timeoutMs = options.timeoutMs ?? Self.defaultTransactionStatusPollTimeoutMs
        let deadlineMs = currentTimeMs() + Double(timeoutMs)
        var lastStatus = TransactionStatusResponse(status: fallbackStatus)
        var completedPolls = 0

        while true {
            do {
                lastStatus = try await signedClient.transactionStatus(
                    TransactionStatusRequest(txnId: txnId)
                ).sdkValue
            } catch let error as CancellationError {
                throw error
            } catch {
                let sdkError = toOMSWalletError(error, operation: .walletTransactionStatus)
                throw OMSWalletError(
                    code: .transactionStatusLookupFailed,
                    message: "Transaction was submitted, but status polling failed",
                    operation: .walletTransactionStatus,
                    status: sdkError.status,
                    txnId: txnId,
                    retryable: true,
                    upstreamError: sdkError.upstreamError,
                    underlyingError: sdkError
                )
            }
            completedPolls += 1

            if lastStatus.status == .executed
                || lastStatus.status == .failed
                || hasTransactionHash(lastStatus.txnHash) {
                return (lastStatus, .resolved)
            }

            let pollDelayMs = transactionStatusPollDelayMs(
                completedPolls: completedPolls,
                options: options
            )
            let remainingMs = deadlineMs - currentTimeMs()
            if remainingMs <= 0 {
                return (lastStatus, .timedOut)
            }

            let sleepMs = min(Double(pollDelayMs), remainingMs)
            try await Task.sleep(nanoseconds: UInt64(sleepMs * 1_000_000))
        }
    }

    private func transactionStatusPollDelayMs(
        completedPolls: Int,
        options: TransactionStatusPollingOptions
    ) -> UInt64 {
        let fastPollCount = options.fastPollCount ?? Self.defaultFastTransactionStatusPollCount
        if completedPolls < fastPollCount {
            return options.fastIntervalMs ?? Self.defaultFastTransactionStatusPollIntervalMs
        }
        return options.intervalMs ?? Self.defaultTransactionStatusPollIntervalMs
    }

    private func currentTimeMs() -> Double {
        currentDate().timeIntervalSince1970 * 1_000
    }

    private func validateTransactionStatusPollingOptions(
        _ options: TransactionStatusPollingOptions
    ) throws {
        if options.intervalMs == 0 {
            throw TransactionError.invalidPollingOption("intervalMs must be greater than zero")
        }
        if options.fastIntervalMs == 0 {
            throw TransactionError.invalidPollingOption("fastIntervalMs must be greater than zero")
        }
        if let fastPollCount = options.fastPollCount, fastPollCount < 0 {
            throw TransactionError.invalidPollingOption("fastPollCount must not be negative")
        }
    }

    private func isSubmittedTransactionResult(_ response: SendTransactionResponse) -> Bool {
        response.status == .executed || hasTransactionHash(response.txnHash)
    }

    private func hasTransactionHash(_ txnHash: String?) -> Bool {
        guard let txnHash = txnHash?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !txnHash.isEmpty
    }

    private func requireActiveEthereumWallet() throws {
        try requireActiveWalletType(.ethereum)
    }

    private func requireActiveSolanaWallet() throws {
        try requireActiveWalletType(.solana)
    }

    private func requireActiveTronWallet() throws {
        try requireActiveWalletType(.tron)
    }

    /// Returns `walletAddress` when given; otherwise the active wallet's address, which must be of
    /// `walletType`. Verification never sends a wallet ID.
    private func verificationWalletAddress(_ walletAddress: String?, walletType: WalletType) throws -> String {
        if let walletAddress {
            return walletAddress
        }
        try requireActiveWalletType(walletType)
        _ = try requireActiveWalletId()
        return try requireActiveWalletAddress()
    }

    /// Checks the stored wallet type, not the address shape.
    func requireActiveWalletType(_ type: WalletType) throws {
        guard let activeWallet else {
            throw OMSWalletError.sessionMissing()
        }
        guard activeWallet.type == type else {
            throw OMSWalletError(
                code: .validationError,
                message: "An active \(type.displayName) wallet is required"
            )
        }
    }
}

private extension WalletType {
    var displayName: String {
        switch self {
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        case .tron: "Tron"
        case .unknown(let value): value
        }
    }
}

// Mirrors the wallet service: it builds the signature from the argument types and accepts only a
// bare function name.
private func requireContractMethodName(_ method: String) throws {
    let isBareName = method.utf8.first.map { $0 == 95 || isASCIILetter($0) } == true
        && method.utf8.allSatisfy { $0 == 95 || isASCIILetter($0) || ($0 >= 48 && $0 <= 57) }
    guard isBareName else {
        throw OMSWalletError(
            code: .validationError,
            message: "method must be a function name such as 'transfer', not a signature; got '\(method)'"
        )
    }
}

private func isASCIILetter(_ byte: UInt8) -> Bool {
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
}

@available(macOS 12.0, iOS 15.0, *)
private extension Array where Element == FeeOption {
    func defaultSelection() -> FeeOptionSelection? {
        first.map { FeeOptionSelection(feeOption: $0, index: 0) }
    }
}

private extension FeeToken {
    var isNativeToken: Bool {
        type.caseInsensitiveCompare("native") == .orderedSame
            || ((contractAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && (tokenId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }

    var balanceDecimals: Int? {
        decimals.map(Int.init) ?? (isNativeToken ? 18 : nil)
    }
}

private enum FeeBalanceNetwork {
    case ethereum(Network)
    case solana(SolanaNetwork)
    case tron(TronNetwork)
}

private func normalizedAddress(_ address: String?) -> String? {
    guard let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed.lowercased()
}

private func normalizedBase58Address(_ address: String?) -> String? {
    guard let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func formatTokenAmount(_ value: String?, decimals: Int?) -> String? {
    guard let value else { return nil }
    guard let decimals else { return value }
    return (try? formatUnits(value: value, decimals: decimals)) ?? value
}
