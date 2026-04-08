import Foundation

extension CompleteAuthReturn {
    static func from(jsonString: String) throws -> CompleteAuthReturn {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Failed to convert string to UTF-8 data")
            )
        }
        return try JSONDecoder().decode(CompleteAuthReturn.self, from: data)
    }
}
