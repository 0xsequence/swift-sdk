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
        try await runOmsOperation(.walletSignMessage) {
            let walletId = try requireActiveWalletId()
            let params = SignMessageRequest(
                network: network.chainId,
                walletId: walletId,
                message: message
            )

            let response = try await signedClient.signMessage(params)
            return response.signature
        }
    }

    public func signTypedData(network: Network, typedData: WebRPCJSONValue) async throws -> String {
        try await runOmsOperation(.walletSignTypedData) {
            let walletId = try requireActiveWalletId()
            let params = SignTypedDataRequest(
                network: network.chainId,
                walletId: walletId,
                typedData: typedData
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
        try await runOmsOperation(.walletIsValidMessageSignature) {
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
        typedData: WebRPCJSONValue,
        signature: String
    ) async throws -> Bool {
        try await runOmsOperation(.walletIsValidTypedDataSignature) {
            let walletId = try requireActiveWalletId()
            let response = try await publicClient.isValidTypedDataSignature(
                IsValidTypedDataSignatureRequest(
                    network: network.chainId,
                    walletAddress: walletAddress,
                    walletId: walletId,
                    typedData: typedData,
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
        mode: TransactionMode = .relayer
    ) async throws -> SendTransactionResponse {
        try await runOmsOperation(.walletSendTransaction) {
            let walletId = try requireActiveWalletId()
            let walletAddress = try activeWalletAddressIfNeeded(for: selectFeeOption)
            return try await sendTransaction(
                network: network,
                request: SendTransactionRequest(
                    to: to,
                    value: value,
                    data: nil,
                    mode: mode
                ),
                selectFeeOption: selectFeeOption,
                walletId: walletId,
                walletAddress: walletAddress
            )
        }
    }

    public func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        selectFeeOption: FeeOptionSelector? = nil
    ) async throws -> SendTransactionResponse {
        try await runOmsOperation(.walletSendTransaction) {
            let walletId = try requireActiveWalletId()
            let walletAddress = try activeWalletAddressIfNeeded(for: selectFeeOption)
            return try await sendTransaction(
                network: network,
                request: request,
                selectFeeOption: selectFeeOption,
                walletId: walletId,
                walletAddress: walletAddress
            )
        }
    }

    private func sendTransaction(
        network: Network,
        request: SendTransactionRequest,
        selectFeeOption: FeeOptionSelector?,
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
                mode: request.mode
            )
        )

        return try await self.execute(
            network: network,
            prepareResponse: prepareResponse,
            feeOptionSelector: selectFeeOption,
            walletAddress: walletAddress
        );
    }

    public func callContract(
        network: Network,
        contract: String,
        method: String,
        args: [AbiArg]?,
        selectFeeOption: FeeOptionSelector? = nil,
        mode: TransactionMode = .relayer
    ) async throws -> SendTransactionResponse {
        try await runOmsOperation(.walletCallContract) {
            let walletId = try requireActiveWalletId()
            let walletAddress = try activeWalletAddressIfNeeded(for: selectFeeOption)
            let prepareResponse = try await signedClient.prepareEthereumContractCall(
                PrepareEthereumContractCallRequest(
                    network: network.chainId,
                    walletId: walletId,
                    contract: contract,
                    method: method,
                    args: args,
                    mode: mode
                )
            )

            return try await self.execute(
                network: network,
                prepareResponse: prepareResponse,
                feeOptionSelector: selectFeeOption,
                walletAddress: walletAddress
            );
        }
    }

    /// Returns the current execution status for a prepared or submitted transaction.
    ///
    /// - Parameter txnId: The transaction ID returned by the wallet API prepare/execute flow.
    /// - Returns: The current transaction status and transaction hash when available.
    public func getTransactionStatus(txnId: String) async throws -> TransactionStatusResponse {
        try await runOmsOperation(.walletGetTransactionStatus) {
            do {
                return try await signedClient.transactionStatus(
                    TransactionStatusRequest(txnId: txnId)
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                throw OmsSdkError(
                    code: .transactionStatusLookupFailed,
                    message: error.localizedDescription,
                    operation: .walletGetTransactionStatus,
                    txnId: txnId,
                    retryable: true,
                    underlyingError: error
                )
            }
        }
    }

    private func execute(
        network: Network,
        prepareResponse: PrepareResponse,
        feeOptionSelector: FeeOptionSelector?,
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
            feeOption: feeOptionSelection
        )

        let executeResponse = try await signedClient.execute(executeRequest)
        var response = SendTransactionResponse(
            txnId: prepareResponse.txnId,
            status: executeResponse.status
        )
        if response.status == .executed {
            return try await getSubmittedTransactionResult(txnId: prepareResponse.txnId)
        }

        for pollIntervalNanos in transactionPollingIntervals {
            guard response.status == .pending else {
                break
            }
            if pollIntervalNanos > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanos)
            }

            let statusResponse = try await getTransactionStatus(txnId: prepareResponse.txnId)
            response = SendTransactionResponse(
                txnId: prepareResponse.txnId,
                status: statusResponse.status,
                txnHash: statusResponse.txnHash
            )

            if isSubmittedTransactionResult(response) {
                return response
            }
        }

        if response.status == .pending {
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
        guard !prepareResponse.sponsored else {
            return nil
        }

        guard !prepareResponse.feeOptions.isEmpty else {
            throw TransactionError.noFeeOptionsAvailable
        }

        guard let feeOptionSelector else {
            guard let feeOptionSelection = prepareResponse.feeOptions.defaultSelection() else {
                throw TransactionError.noFeeOptionsAvailable
            }
            return feeOptionSelection
        }

        guard let walletAddress else {
            throw OmsSdkError.sessionMissing()
        }

        let feeOptionSelection = try await feeOptionSelector(
            enrichFeeOptionsWithBalances(
                network: network,
                walletAddress: walletAddress,
                feeOptions: prepareResponse.feeOptions
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
        let nativeBalance: TokenBalance?
        if feeOptions.contains(where: { $0.token.isNativeToken }) {
            nativeBalance = await loadNativeTokenBalance(
                network: network,
                walletAddress: walletAddress
            )
        } else {
            nativeBalance = nil
        }

        var balancesByContract: [String: TokenBalance?] = [:]
        let contractAddresses = feeOptions
            .compactMap { normalizedAddress($0.token.contractAddress) }
            .reduce(into: [String]()) { addresses, address in
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }

        for contractAddress in contractAddresses {
            balancesByContract[contractAddress] = await loadTokenBalanceOrZero(
                network: network,
                contractAddress: contractAddress,
                walletAddress: walletAddress
            )
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

    private func loadNativeTokenBalance(
        network: Network,
        walletAddress: String
    ) async -> TokenBalance? {
        try? await indexerClient.getNativeTokenBalance(
            network: network,
            walletAddress: walletAddress
        )
    }

    private func loadTokenBalanceOrZero(
        network: Network,
        contractAddress: String,
        walletAddress: String
    ) async -> TokenBalance? {
        do {
            let result = try await indexerClient.getTokenBalances(
                network: network,
                contractAddress: contractAddress,
                walletAddress: walletAddress,
                includeMetadata: false,
                page: TokenBalancesPageRequest()
            )
            return result.balances.first {
                normalizedAddress($0.contractAddress) == contractAddress
            } ?? TokenBalance(
                contractType: "ERC20",
                contractAddress: contractAddress,
                accountAddress: walletAddress,
                tokenId: nil,
                balance: "0",
                blockHash: nil,
                blockNumber: nil,
                chainId: Int64(network.chainId)
            )
        } catch {
            return nil
        }
    }

    private func getSubmittedTransactionResult(txnId: String) async throws -> SendTransactionResponse {
        let statusResponse = try await getTransactionStatus(txnId: txnId)
        let response = SendTransactionResponse(
            txnId: txnId,
            status: statusResponse.status,
            txnHash: statusResponse.txnHash
        )

        guard isSubmittedTransactionResult(response) else {
            throw TransactionError.transactionFailed(status: statusResponse.status)
        }

        return response
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
