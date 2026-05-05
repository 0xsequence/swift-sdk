import Foundation

extension Decodable {
    static func from(jsonString: String, decoder: JSONDecoder = JSONDecoder()) throws -> Self {
        try decoder.decode(Self.self, from: Data(jsonString.utf8))
    }
}
