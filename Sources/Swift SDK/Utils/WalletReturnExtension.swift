import Foundation

extension WalletReturn {
    static func from(jsonString: String) throws -> WalletReturn {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Failed to convert string to UTF-8 data")
            )
        }
        return try JSONDecoder().decode(WalletReturn.self, from: data)
    }
}
