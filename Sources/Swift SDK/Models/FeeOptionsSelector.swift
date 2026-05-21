import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct FeeOptionWithBalance: Sendable {
    public let feeOption: FeeOption
    public let balance: TokenBalance?
    public let available: String?
    public let availableRaw: String?
    public let decimals: Int?

    public init(
        feeOption: FeeOption,
        balance: TokenBalance? = nil,
        available: String? = nil,
        availableRaw: String? = nil,
        decimals: Int? = nil
    ) {
        self.feeOption = feeOption
        self.balance = balance
        self.available = available
        self.availableRaw = availableRaw
        self.decimals = decimals
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct FeeOptionSelector: Sendable {
    public typealias Select = @Sendable (_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection?

    private let select: Select
    public init(_ select: @escaping Select) { self.select = select }

    public func callAsFunction(_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection? {
        guard !options.isEmpty else { return nil }
        return try await select(options)
    }

    public func callAsFunction(_ options: [FeeOption]) async throws -> FeeOptionSelection? {
        try await callAsFunction(options.map { FeeOptionWithBalance(feeOption: $0) })
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension FeeOptionSelector {
    static let first = FeeOptionSelector { options in
        options.first.map { FeeOptionSelection(token: $0.feeOption.token.symbol) }
    }

    static let cheapest = FeeOptionSelector { options in
        options
            .min(by: { isNumericValueLessThan($0.feeOption.value, $1.feeOption.value) })
            .map { FeeOptionSelection(token: $0.feeOption.token.symbol) }
    }

    static func custom(_ pick: @escaping Select) -> FeeOptionSelector {
        FeeOptionSelector(pick)
    }

    private static func isNumericValueLessThan(_ lhs: String, _ rhs: String) -> Bool {
        guard let normalizedLhs = normalizedUnsignedDecimal(lhs),
              let normalizedRhs = normalizedUnsignedDecimal(rhs) else {
            return lhs < rhs
        }

        if normalizedLhs.count != normalizedRhs.count {
            return normalizedLhs.count < normalizedRhs.count
        }

        return normalizedLhs < normalizedRhs
    }

    private static func normalizedUnsignedDecimal(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.utf8.allSatisfy({ byte in
            byte >= CharacterByte.zero && byte <= CharacterByte.nine
        }) else {
            return nil
        }

        let normalized = trimmed.drop(while: { $0 == "0" })
        return normalized.isEmpty ? "0" : String(normalized)
    }
}

private enum CharacterByte {
    static let zero = Character("0").asciiValue!
    static let nine = Character("9").asciiValue!
}
