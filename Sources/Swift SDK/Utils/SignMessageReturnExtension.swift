import Foundation

extension SignMessageReturn {
    static func from(jsonString: String) throws -> SignMessageReturn {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Failed to convert string to UTF-8 data")
            )
        }
        return try JSONDecoder().decode(SignMessageReturn.self, from: data)
    }
}
