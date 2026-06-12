public struct TokenBalancesPage: Codable, Sendable {
    public let page: Int
    public let pageSize: Int
    public let more: Bool

    public init(page: Int, pageSize: Int, more: Bool) {
        self.page = page
        self.pageSize = pageSize
        self.more = more
    }
}
