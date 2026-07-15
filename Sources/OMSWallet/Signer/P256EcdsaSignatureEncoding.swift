import Foundation

enum P256EcdsaSignatureEncoding {
    enum EncodingError: Error {
        case invalidSignature
    }

    static func derToRaw(_ derSignature: Data) throws -> [UInt8] {
        var reader = DerReader(Array(derSignature))
        try reader.expectTag(sequenceTag)
        let sequenceEnd = try reader.readLengthEnd()
        let r = try reader.readInteger()
        let s = try reader.readInteger()

        guard reader.position == sequenceEnd && reader.position == derSignature.count else {
            throw EncodingError.invalidSignature
        }

        return r + s
    }

    private struct DerReader {
        private let source: [UInt8]
        private(set) var position: Int = 0

        init(_ source: [UInt8]) {
            self.source = source
        }

        mutating func expectTag(_ tag: UInt8) throws {
            guard try readByte() == tag else {
                throw EncodingError.invalidSignature
            }
        }

        mutating func readLengthEnd() throws -> Int {
            let length = try readLength()
            let end = position + length
            guard end <= source.count else {
                throw EncodingError.invalidSignature
            }
            return end
        }

        mutating func readInteger() throws -> [UInt8] {
            try expectTag(integerTag)
            let length = try readLength()
            guard length > 0 && position + length <= source.count else {
                throw EncodingError.invalidSignature
            }

            let encoded = Array(source[position..<(position + length)])
            position += length

            guard encoded[0] & 0x80 == 0 else {
                throw EncodingError.invalidSignature
            }
            guard encoded.count == 1 || encoded[0] != 0 || encoded[1] & 0x80 != 0 else {
                throw EncodingError.invalidSignature
            }

            let unsigned: [UInt8]
            if encoded.count > 1 && encoded[0] == 0 {
                unsigned = Array(encoded.dropFirst())
            } else {
                unsigned = encoded
            }

            guard unsigned.count <= p256FieldSizeBytes else {
                throw EncodingError.invalidSignature
            }

            return Array(repeating: 0, count: p256FieldSizeBytes - unsigned.count) + unsigned
        }

        private mutating func readLength() throws -> Int {
            let first = Int(try readByte())
            if first & 0x80 == 0 {
                return first
            }

            let byteCount = first & 0x7f
            guard (1...2).contains(byteCount), position + byteCount <= source.count else {
                throw EncodingError.invalidSignature
            }

            var length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(try readByte())
            }
            guard length >= 0x80 else {
                throw EncodingError.invalidSignature
            }
            return length
        }

        private mutating func readByte() throws -> UInt8 {
            guard position < source.count else {
                throw EncodingError.invalidSignature
            }
            defer { position += 1 }
            return source[position]
        }
    }

    private static let p256FieldSizeBytes = 32
    private static let sequenceTag: UInt8 = 0x30
    private static let integerTag: UInt8 = 0x02
}
