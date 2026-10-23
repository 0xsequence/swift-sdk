class ByteUtils {
    /// Converts a byte array to a lowercase hexadecimal string.
    /// - Parameter data: The bytes to encode.
    /// - Returns: A hex string, e.g. `[0xDE, 0xAD]` → `"dead"`.
    public static func bytesToHex(data: [UInt8]) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
