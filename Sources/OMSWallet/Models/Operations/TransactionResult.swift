@available(macOS 12.0, iOS 15.0, *)
public struct TransactionStatusPollingOptions: Sendable, Equatable {
    public let timeoutMs: UInt64?
    public let intervalMs: UInt64?
    public let fastIntervalMs: UInt64?
    public let fastPollCount: Int?

    public init(
        timeoutMs: UInt64? = nil,
        intervalMs: UInt64? = nil,
        fastIntervalMs: UInt64? = nil,
        fastPollCount: Int? = nil
    ) {
        self.timeoutMs = timeoutMs
        self.intervalMs = intervalMs
        self.fastIntervalMs = fastIntervalMs
        self.fastPollCount = fastPollCount
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct SendTransactionResponse: Codable, Sendable, Equatable {
    public let txnId: String
    public let status: TransactionStatus
    public let txnHash: String?

    public init(txnId: String, status: TransactionStatus, txnHash: String? = nil) {
        self.txnId = txnId
        self.status = status
        self.txnHash = txnHash
    }
}
