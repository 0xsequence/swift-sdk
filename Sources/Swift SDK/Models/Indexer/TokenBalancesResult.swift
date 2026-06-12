public struct TokenBalancesResult: Sendable {
    public let status: Int
    public let page: TokenBalancesPage?
    public let balances: [TokenBalance]

    public init(status: Int, page: TokenBalancesPage?, balances: [TokenBalance]) {
        self.status = status
        self.page = page
        self.balances = balances
    }
}
