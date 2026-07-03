import Foundation

@available(macOS 12.0, iOS 15.0, *)
public enum WalletSelectionBehavior: String, Codable, Equatable, Sendable {
    case automatic
    case manual
}
