@available(macOS 12.0, iOS 15.0, *)
public struct TransactionResult: Codable, Sendable, Equatable {
    public let txnId: String
    public let status: TransactionStatus
    public let txnHash: String

    public init(txnId: String, status: TransactionStatus, txnHash: String) {
        self.txnId = txnId
        self.status = status
        self.txnHash = txnHash
    }
}
