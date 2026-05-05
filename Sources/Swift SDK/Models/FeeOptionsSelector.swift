import Foundation

@available(macOS 12.0, iOS 15.0, *)
public struct FeeOptionSelector : Sendable{
    public typealias Select = @Sendable (_ options: [FeeOption]) async throws -> FeeOption

    private let select: Select
    public init(_ select: @escaping Select) { self.select = select }

    public func callAsFunction(_ options: [FeeOption]) async throws -> FeeOption {
        guard !options.isEmpty else {
            throw TransactionError.noFeeOptionsAvailable
        }
        return try await select(options)
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension FeeOptionSelector {
    static let first = FeeOptionSelector { options in
        options.first!  // safe — emptiness is checked in callAsFunction
    }

    static let cheapest = FeeOptionSelector { options in
        options.min(by: { isNumericValueLessThan($0.value, $1.value) })!
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
