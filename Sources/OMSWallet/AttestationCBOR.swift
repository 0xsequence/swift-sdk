import Foundation

enum AttestationCBOR {
    indirect enum Value {
        case unsigned(UInt64)
        case negative(UInt64)
        case byteString(Data)
        case textString(String)
        case array([Value])
        case map([(Value, Value)])
        case tagged(UInt64, Value)
        case boolean(Bool)
        case null

        func value(forTextKey key: String) -> Value? {
            guard case .map(let entries) = self else { return nil }
            return entries.first { entry in
                guard case .textString(let candidate) = entry.0 else { return false }
                return candidate == key
            }?.1
        }

        func value(forUnsignedKey key: UInt64) -> Value? {
            guard case .map(let entries) = self else { return nil }
            return entries.first { entry in
                guard case .unsigned(let candidate) = entry.0 else { return false }
                return candidate == key
            }?.1
        }
    }

    enum CodingError: Error {
        case invalidData
    }

    private static let maxNestingDepth = 16
    private static let maxCollectionCount = 256
    private static let maxDataLength = 1_048_576

    static func decode(_ data: Data) throws -> Value {
        var decoder = Decoder(bytes: [UInt8](data))
        let value = try decoder.decode(depth: 0)
        guard decoder.isAtEnd else { throw CodingError.invalidData }
        return value
    }

    static func encode(_ value: Value) throws -> Data {
        var encoder = Encoder()
        try encoder.encode(value, depth: 0)
        return Data(encoder.bytes)
    }

    private struct Decoder {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index == bytes.count }

        mutating func decode(depth: Int) throws -> Value {
            guard depth <= maxNestingDepth else { throw CodingError.invalidData }
            let initial = try readByte()
            let majorType = initial >> 5
            let additionalInfo = initial & 0x1f

            switch majorType {
            case 0:
                return .unsigned(try readArgument(additionalInfo))
            case 1:
                return .negative(try readArgument(additionalInfo))
            case 2:
                return .byteString(Data(try readBytes(count: try dataLength(additionalInfo))))
            case 3:
                let data = Data(try readBytes(count: try dataLength(additionalInfo)))
                guard let string = String(data: data, encoding: .utf8) else { throw CodingError.invalidData }
                return .textString(string)
            case 4:
                let count = try collectionLength(additionalInfo)
                var values: [Value] = []
                values.reserveCapacity(count)
                for _ in 0..<count {
                    try values.append(decode(depth: depth + 1))
                }
                return .array(values)
            case 5:
                let count = additionalInfo == 31 ? nil : try collectionLength(additionalInfo)
                var entries: [(Value, Value)] = []
                var keys = Set<MapKey>()
                entries.reserveCapacity(count ?? 0)
                while count.map({ entries.count < $0 }) ?? true {
                    if count == nil, try peekByte() == 0xff {
                        _ = try readByte()
                        break
                    }
                    guard entries.count < maxCollectionCount else { throw CodingError.invalidData }
                    let key = try decode(depth: depth + 1)
                    guard let mapKey = MapKey(key), keys.insert(mapKey).inserted else {
                        throw CodingError.invalidData
                    }
                    let value = try decode(depth: depth + 1)
                    entries.append((key, value))
                }
                return .map(entries)
            case 6:
                return .tagged(try readArgument(additionalInfo), try decode(depth: depth + 1))
            case 7:
                switch additionalInfo {
                case 20: return .boolean(false)
                case 21: return .boolean(true)
                case 22: return .null
                default: throw CodingError.invalidData
                }
            default:
                throw CodingError.invalidData
            }
        }

        private mutating func collectionLength(_ additionalInfo: UInt8) throws -> Int {
            let length = try readArgument(additionalInfo)
            guard length <= UInt64(maxCollectionCount), let count = Int(exactly: length) else {
                throw CodingError.invalidData
            }
            return count
        }

        private mutating func dataLength(_ additionalInfo: UInt8) throws -> Int {
            let length = try readArgument(additionalInfo)
            guard length <= UInt64(maxDataLength), let count = Int(exactly: length) else {
                throw CodingError.invalidData
            }
            return count
        }

        private mutating func readArgument(_ additionalInfo: UInt8) throws -> UInt64 {
            switch additionalInfo {
            case 0...23:
                return UInt64(additionalInfo)
            case 24:
                return UInt64(try readByte())
            case 25:
                return try readInteger(byteCount: 2)
            case 26:
                return try readInteger(byteCount: 4)
            case 27:
                return try readInteger(byteCount: 8)
            default:
                throw CodingError.invalidData
            }
        }

        private mutating func readInteger(byteCount: Int) throws -> UInt64 {
            var value: UInt64 = 0
            for _ in 0..<byteCount {
                value = (value << 8) | UInt64(try readByte())
            }
            return value
        }

        private mutating func readByte() throws -> UInt8 {
            guard index < bytes.count else { throw CodingError.invalidData }
            defer { index += 1 }
            return bytes[index]
        }

        private func peekByte() throws -> UInt8 {
            guard index < bytes.count else { throw CodingError.invalidData }
            return bytes[index]
        }

        private mutating func readBytes(count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, count <= bytes.count - index else { throw CodingError.invalidData }
            let start = index
            index += count
            return bytes[start..<index]
        }
    }

    private struct Encoder {
        var bytes: [UInt8] = []

        mutating func encode(_ value: Value, depth: Int) throws {
            guard depth <= maxNestingDepth else { throw CodingError.invalidData }
            switch value {
            case .unsigned(let value):
                appendArgument(majorType: 0, value: value)
            case .negative(let value):
                appendArgument(majorType: 1, value: value)
            case .byteString(let data):
                try appendCollectionHeader(majorType: 2, count: data.count)
                bytes.append(contentsOf: data)
            case .textString(let string):
                let encoded = Array(string.utf8)
                try appendCollectionHeader(majorType: 3, count: encoded.count)
                bytes.append(contentsOf: encoded)
            case .array(let values):
                try appendCollectionHeader(majorType: 4, count: values.count)
                for value in values {
                    try encode(value, depth: depth + 1)
                }
            case .map(let entries):
                try appendCollectionHeader(majorType: 5, count: entries.count)
                var keys = Set<MapKey>()
                for (key, value) in entries {
                    guard let mapKey = MapKey(key), keys.insert(mapKey).inserted else {
                        throw CodingError.invalidData
                    }
                    try encode(key, depth: depth + 1)
                    try encode(value, depth: depth + 1)
                }
            case .tagged(let tag, let value):
                appendArgument(majorType: 6, value: tag)
                try encode(value, depth: depth + 1)
            case .boolean(let value):
                bytes.append(value ? 0xf5 : 0xf4)
            case .null:
                bytes.append(0xf6)
            }
        }

        private mutating func appendCollectionHeader(majorType: UInt8, count: Int) throws {
            let limit = majorType == 2 || majorType == 3 ? maxDataLength : maxCollectionCount
            guard count <= limit else { throw CodingError.invalidData }
            appendArgument(majorType: majorType, value: UInt64(count))
        }

        private mutating func appendArgument(majorType: UInt8, value: UInt64) {
            let prefix = majorType << 5
            switch value {
            case 0...23:
                bytes.append(prefix | UInt8(value))
            case 24...UInt64(UInt8.max):
                bytes.append(prefix | 24)
                bytes.append(UInt8(value))
            case 256...UInt64(UInt16.max):
                bytes.append(prefix | 25)
                appendInteger(value, byteCount: 2)
            case 65_536...UInt64(UInt32.max):
                bytes.append(prefix | 26)
                appendInteger(value, byteCount: 4)
            default:
                bytes.append(prefix | 27)
                appendInteger(value, byteCount: 8)
            }
        }

        private mutating func appendInteger(_ value: UInt64, byteCount: Int) {
            for shift in stride(from: (byteCount - 1) * 8, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
    }

    private enum MapKey: Hashable {
        case unsigned(UInt64)
        case negative(UInt64)
        case byteString(Data)
        case textString(String)

        init?(_ value: Value) {
            switch value {
            case .unsigned(let value): self = .unsigned(value)
            case .negative(let value): self = .negative(value)
            case .byteString(let value): self = .byteString(value)
            case .textString(let value): self = .textString(value)
            default: return nil
            }
        }
    }
}
