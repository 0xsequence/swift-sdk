public struct TokenBalancesPageRequest: Codable, Sendable {
    public let page: Int?
    public let pageSize: Int?

    public init(page: Int? = nil, pageSize: Int? = nil) {
        self.page = page
        self.pageSize = pageSize
    }
}
