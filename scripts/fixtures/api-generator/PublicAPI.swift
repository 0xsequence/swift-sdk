import Foundation

public struct Wallet: Sendable {
    public func sign(_ value: String) {}
    public func sign(_ value: Data) {}
}

public final class AccessFixture {
    public let identifier = "fixture"
    public internal(set) var selectedWallet: String?
}

@discardableResult
public func attributedOperation() -> Bool { true }

public protocol FixtureProtocol {}

public struct SameModuleConformer: FixtureProtocol {}

public enum RawStatus: String, Sendable {
    case ready = "ready-value"
    case waiting = "waiting-value"
}

public final class UnsafeWallet: FixtureProtocol, @unchecked Sendable {}

public enum UnsupportedCases {
    case first, second
}
