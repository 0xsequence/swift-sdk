import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct FeeOptionWithBalance: Sendable {
    public let feeOption: FeeOption
    public let selection: FeeOptionSelection
    public let balance: TokenBalance?
    public let available: String?
    public let availableRaw: String?
    public let decimals: Int?

    public init(
        feeOption: FeeOption,
        selection: FeeOptionSelection? = nil,
        balance: TokenBalance? = nil,
        available: String? = nil,
        availableRaw: String? = nil,
        decimals: Int? = nil
    ) {
        self.feeOption = feeOption
        self.selection = selection ?? FeeOptionSelection(feeOption: feeOption)
        self.balance = balance
        self.available = available
        self.availableRaw = availableRaw
        self.decimals = decimals
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension FeeOptionSelection {
    init(feeOption: FeeOption, index: UInt32? = nil) {
        let tokenId = feeOption.token.tokenId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tokenId, !tokenId.isEmpty {
            self.init(token: tokenId, index: index)
        } else {
            self.init(token: feeOption.token.symbol, index: index)
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public struct FeeOptionSelector: Sendable {
    /// Sponsored transactions pass an empty array. Returning `nil` acknowledges the free fee;
    /// throw to stop execution.
    public typealias Select = @Sendable (_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection?

    private let select: Select
    public init(_ select: @escaping Select) { self.select = select }

    public func callAsFunction(_ options: [FeeOptionWithBalance]) async throws -> FeeOptionSelection? {
        return try await select(options)
    }

    public func callAsFunction(_ options: [FeeOption]) async throws -> FeeOptionSelection? {
        try await callAsFunction(options.map { FeeOptionWithBalance(feeOption: $0) })
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension FeeOptionSelector {
    static let firstAvailable = FeeOptionSelector { options in
        options.first { option in
            guard let availableRaw = option.availableRaw else {
                return false
            }
            return hasEnoughBalance(availableRaw, feeValue: option.feeOption.value)
        }?
        .selection
    }

    static func custom(_ pick: @escaping Select) -> FeeOptionSelector {
        FeeOptionSelector(pick)
    }

    private static func hasEnoughBalance(_ availableRaw: String, feeValue: String) -> Bool {
        guard let available = normalizedUnsignedDecimal(availableRaw),
              let fee = normalizedUnsignedDecimal(feeValue) else {
            return false
        }

        if available.count != fee.count {
            return available.count > fee.count
        }

        return available >= fee
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
