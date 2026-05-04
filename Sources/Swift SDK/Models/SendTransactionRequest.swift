public struct SendTransactionRequest {
    public let to: String
    public let value: String
    public let data: String?

    public init(to: String, value: String, data: String? = nil) {
        self.to = to
        self.value = value
        self.data = data
    }
}
