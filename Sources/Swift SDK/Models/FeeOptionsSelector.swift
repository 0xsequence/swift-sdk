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
        options.min(by: { $0.value < $1.value })!
    }

    static func custom(_ pick: @escaping Select) -> FeeOptionSelector {
        FeeOptionSelector(pick)
    }
}
