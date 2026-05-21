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

@available(macOS 12.0, iOS 15.0, *)
@available(*, deprecated, renamed: "SendTransactionResponse")
public typealias TransactionResult = SendTransactionResponse
