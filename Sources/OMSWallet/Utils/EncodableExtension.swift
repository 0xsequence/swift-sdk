import Foundation

extension Encodable {
    func jsonString(pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
