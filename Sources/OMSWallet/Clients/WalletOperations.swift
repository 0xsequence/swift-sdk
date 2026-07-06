import Foundation

@available(macOS 12.0, iOS 15.0, *)
extension WalletClient {
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: Network, message: String) async throws -> String {
        try await runOMSWalletOperation(.walletSignMessage) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = SignMessageRequest(
                network: network.chainId,
                walletId: walletId,
                message: message
            )

            let response = try await signedClient.signMessage(params)
            return response.signature
        }
    }

    public func signTypedData(network: Network, typedData: JSONValue) async throws -> String {
        try await runOMSWalletOperation(.walletSignTypedData) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let params = SignTypedDataRequest(
                network: network.chainId,
                walletId: walletId,
                typedData: typedData.waasValue
            )

            let response = try await signedClient.signTypedData(params)
            return response.signature
        }
    }

    public func isValidMessageSignature(
        network: Network,
        walletAddress: String,
        message: String,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidMessageSignature) {
            let walletId = try requireActiveWalletId()
            let response = try await publicClient.isValidMessageSignature(
                IsValidMessageSignatureRequest(
                    network: network.chainId,
                    walletAddress: walletAddress,
                    walletId: walletId,
                    message: message,
                    signature: signature
                )
            )

            return response.isValid
        }
    }

    public func isValidTypedDataSignature(
        network: Network,
        walletAddress: String,
        typedData: JSONValue,
        signature: String
    ) async throws -> Bool {
        try await runOMSWalletOperation(.walletIsValidTypedDataSignature) {
            let walletId = try requireActiveWalletId()
            let response = try await publicClient.isValidTypedDataSignature(
                IsValidTypedDataSignatureRequest(
                    network: network.chainId,
                    walletAddress: walletAddress,
                    walletId: walletId,
                    typedData: typedData.waasValue,
                    signature: signature
                )
            )

            return response.isValid
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
                network: network.chainId,
                walletId: walletId,
                to: request.to,
                value: request.value,
                data: request.data,
                mode: request.mode.waasValue
            )
        )

        return try await self.execute(
            network: network,
            prepareResponse: prepareResponse,
            feeOptionSelector: selectFeeOption,
            waitForStatus: waitForStatus,
            statusPolling: statusPolling,
            walletAddress: walletAddress
        )
    }

    public func callContract(
        network: Network,
        contract: String,
        method: String,
        args: [AbiArg]?,
        selectFeeOption: FeeOptionSelector? = nil,
        mode: TransactionMode = .relayer,
        waitForStatus: Bool = true,
        statusPolling: TransactionStatusPollingOptions = TransactionStatusPollingOptions()
    ) async throws -> SendTransactionResponse {
        try await runOMSWalletOperation(.walletCallContract) {
            let walletId = try requireActiveWalletId()
            try requireActiveCredential()
            let walletAddress = try walletAddressIfNeeded(for: selectFeeOption)
            let prepareResponse = try await signedClient.prepareEthereumContractCall(
                PrepareEthereumContractCallRequest(
                    network: network.chainId,
                    walletId: walletId,
                    contract: contract,
                    method: method,
                    args: args?.map { $0.waasValue },
                    mode: mode.waasValue
                )
            )

            return try await self.execute(
                network: network,
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
        network: Network,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        waitForStatus: Bool,
        statusPolling: TransactionStatusPollingOptions,
        walletAddress: String?
    ) async throws -> SendTransactionResponse {
        let feeOptionSelection = try await selectFeeOption(
            network: network,
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
                status: executeResponse.status.sdkValue
            )
        }

        let statusResponse = try await waitForTransactionStatus(
            txnId: prepareResponse.txnId,
            fallbackStatus: executeResponse.status.sdkValue,
            options: statusPolling
        )
        let response = SendTransactionResponse(
            txnId: prepareResponse.txnId,
            status: statusResponse.status,
            txnHash: statusResponse.txnHash
        )

        if isSubmittedTransactionResult(response) {
            return response
        }

        if response.status == .pending || response.status == .failed {
            return response
        }

        throw TransactionError.transactionFailed(status: response.status)
    }

    private func selectFeeOption(
        network: Network,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
        walletAddress: String?
    ) async throws -> FeeOptionSelection? {
        let feeOptions = prepareResponse.feeOptions.map { $0.sdkValue }
        guard !prepareResponse.sponsored else {
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

        guard let walletAddress else {
            throw OMSWalletError.sessionMissing()
        }

        let feeOptionSelection = try await feeOptionSelector(
            enrichFeeOptionsWithBalances(
                network: network,
                walletAddress: walletAddress,
                feeOptions: feeOptions
            )
        )

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
            ? balances?.nativeBalances.first { $0.chainId == Int64(network.id) }
            : nil

        var balancesByContract: [String: TokenBalance?] = [:]
        for contractAddress in contractAddresses {
            balancesByContract[contractAddress] = balances.map { balances in
                balances.balances.first {
                    normalizedAddress($0.contractAddress) == contractAddress
                } ?? TokenBalance(
                    contractType: "ERC20",
                    contractAddress: contractAddress,
                    accountAddress: walletAddress,
                    tokenId: nil,
                    balance: "0",
                    blockHash: nil,
                    blockNumber: nil,
                    chainId: Int64(network.id)
                )
            }
        }

        return feeOptions.map { feeOption in
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
                balance: balance,
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
    ) async throws -> TransactionStatusResponse {
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
                return lastStatus
            }

            let pollDelayMs = transactionStatusPollDelayMs(
                completedPolls: completedPolls,
                options: options
            )
            if pollDelayMs == 0 {
                return lastStatus
            }

            let remainingMs = deadlineMs - currentTimeMs()
            if remainingMs <= 0 {
                return lastStatus
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

    private func isSubmittedTransactionResult(_ response: SendTransactionResponse) -> Bool {
        response.status == .executed || hasTransactionHash(response.txnHash)
    }

    private func hasTransactionHash(_ txnHash: String?) -> Bool {
        guard let txnHash = txnHash?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !txnHash.isEmpty
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension Array where Element == FeeOption {
    func defaultSelection() -> FeeOptionSelection? {
        first.map { FeeOptionSelection(feeOption: $0) }
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

private func normalizedAddress(_ address: String?) -> String? {
    guard let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed.lowercased()
}

private func formatTokenAmount(_ value: String?, decimals: Int?) -> String? {
    guard let value else { return nil }
    guard let decimals else { return value }
    return (try? formatUnits(value: value, decimals: decimals)) ?? value
}
