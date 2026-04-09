class ByteUtils {
    /// Converts a byte array to a lowercase hexadecimal string.
    /// - Parameter data: The bytes to encode.
    /// - Returns: A hex string, e.g. `[0xDE, 0xAD]` → `"dead"`.
    public static func BytesToHex(data: [UInt8]) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Converts a hexadecimal string to a byte array.
    /// - Parameter hex: A hex string (case-insensitive, with or without `0x` prefix).
    /// - Returns: The corresponding bytes, or an empty array if the string is invalid.
    public static func HexToBytes(hex: String) -> [UInt8] {
        var sanitised = hex.lowercased()
        if sanitised.hasPrefix("0x") { sanitised = String(sanitised.dropFirst(2)) }
        guard sanitised.count.isMultiple(of: 2) else { return [] }

        return stride(from: 0, to: sanitised.count, by: 2).compactMap { i in
            let start = sanitised.index(sanitised.startIndex, offsetBy: i)
            let end   = sanitised.index(start, offsetBy: 2)
            return UInt8(sanitised[start..<end], radix: 16)
        }
    }
}
