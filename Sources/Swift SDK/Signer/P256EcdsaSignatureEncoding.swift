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

    static func rawToDer(_ rawSignature: [UInt8]) throws -> Data {
        guard rawSignature.count == rawSignatureSizeBytes else {
            throw EncodingError.invalidSignature
        }

        let r = try Array(rawSignature[0..<p256FieldSizeBytes]).toDerInteger()
        let s = try Array(rawSignature[p256FieldSizeBytes..<rawSignatureSizeBytes]).toDerInteger()
        let body = r + s
        return Data([sequenceTag] + encodeLength(body.count) + body)
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

    private static func encodeLength(_ length: Int) -> [UInt8] {
        precondition(length >= 0)
        if length < 0x80 {
            return [UInt8(length)]
        }

        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.append(UInt8(remaining & 0xff))
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + Array(bytes.reversed())
    }

    private static let p256FieldSizeBytes = 32
    private static let rawSignatureSizeBytes = 64
    private static let sequenceTag: UInt8 = 0x30
    private static let integerTag: UInt8 = 0x02
}

private extension Array where Element == UInt8 {
    func toDerInteger() throws -> [UInt8] {
        let trimmed = dropLeadingZeroes()
        let positive: [UInt8]
        if trimmed[0] & 0x80 != 0 {
            positive = [0] + trimmed
        } else {
            positive = trimmed
        }
        return [0x02] + P256EcdsaSignatureEncoding.encodeLengthForInteger(positive.count) + positive
    }

    func dropLeadingZeroes() -> [UInt8] {
        guard let firstNonZero = firstIndex(where: { $0 != 0 }) else {
            return [0]
        }
        return Array(self[firstNonZero...])
    }
}

private extension P256EcdsaSignatureEncoding {
    static func encodeLengthForInteger(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        }

        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.append(UInt8(remaining & 0xff))
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + Array(bytes.reversed())
    }
}
