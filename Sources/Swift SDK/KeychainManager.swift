import Foundation
import Security

/// A simple wrapper for reading and writing `String` values to the iOS/macOS Keychain.
final class KeychainManager {

    // MARK: - Shared Instance

    @MainActor static let shared = KeychainManager()

    private init() {}

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case unexpectedData
        case unhandledError(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                return "The keychain returned data in an unexpected format."
            case .unhandledError(let status):
                return "Keychain error with OSStatus: \(status)."
            }
        }
    }

    // MARK: - Write

    /// Saves (or updates) a string value for the given key.
    /// - Parameters:
    ///   - value: The string to store.
    ///   - key: A unique identifier for this item.
    ///   - service: The service name used to namespace the item (defaults to the bundle identifier).
    @discardableResult
    func set(_ value: String, forKey key: String, service: String = bundleID) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Try to update an existing item first.
        let query = baseQuery(forKey: key, service: service)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return true

        case errSecItemNotFound:
            // Item doesn't exist yet — add it.
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
            return true

        default:
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    // MARK: - Read

    /// Retrieves the string stored for the given key, or `nil` if not found.
    /// - Parameters:
    ///   - key: The unique identifier for this item.
    ///   - service: The service name used to namespace the item (defaults to the bundle identifier).
    func string(forKey key: String, service: String = bundleID) throws -> String? {
        var query = baseQuery(forKey: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return string

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - Delete

    /// Removes the keychain item for the given key.
    /// - Parameters:
    ///   - key: The unique identifier for this item.
    ///   - service: The service name used to namespace the item (defaults to the bundle identifier).
    @discardableResult
    func delete(forKey key: String, service: String = bundleID) throws -> Bool {
        let query = baseQuery(forKey: key, service: service)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
        return status == errSecSuccess
    }

    // MARK: - Helpers

    private static let bundleID: String = Bundle.main.bundleIdentifier ?? "com.app.keychain"

    private func baseQuery(forKey key: String, service: String) -> [String: Any] {
        [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : key
        ]
    }
}
