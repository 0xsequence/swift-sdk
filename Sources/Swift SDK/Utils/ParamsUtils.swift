import Foundation

extension Encodable {
    func toJSONString(pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = .prettyPrinted
        }
        let data = try encoder.encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: [], debugDescription: "Failed to convert data to UTF-8 string")
            )
        }
        return jsonString
    }
}
