public struct SendTransactionRequest: Sendable {
    public let to: String
    public let value: String
    public let data: String?
    public let mode: TransactionMode

    public init(to: String, value: String, data: String? = nil, mode: TransactionMode = .relayer) {
        self.to = to
        self.value = value
        self.data = data
        self.mode = mode
    }
}
