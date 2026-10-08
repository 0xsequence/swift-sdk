import Foundation

extension Decodable {
    static func from(jsonString: String, decoder: JSONDecoder = JSONDecoder()) throws -> Self {
        try decoder.decode(Self.self, from: Data(jsonString.utf8))
    }
}

extension KeyedDecodingContainer {
    /// Decodes an optional string, treating an empty string as absent.
    func decodeNonEmptyString(forKey key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty else {
            return nil
        }
        return value
    }
}
