public struct TokenBalancesPage: Codable, Sendable {
    public let page: Int?
    public let column: String?
    public let before: JSONValue?
    public let after: JSONValue?
    public let sort: [SortBy]?
    public let pageSize: Int?
    public let more: Bool?

    public init(
        page: Int? = nil,
        column: String? = nil,
        before: JSONValue? = nil,
        after: JSONValue? = nil,
        sort: [SortBy]? = nil,
        pageSize: Int? = nil,
        more: Bool? = nil
    ) {
        self.page = page
        self.column = column
        self.before = before
        self.after = after
        self.sort = sort
        self.pageSize = pageSize
        self.more = more
    }
}
