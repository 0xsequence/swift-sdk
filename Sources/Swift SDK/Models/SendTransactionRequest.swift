public struct SendTransactionRequest {
    public let to: String
    public let value: String
    public let data: String?
    public let feeCeiling: String?
    public let nonce: String?
}
