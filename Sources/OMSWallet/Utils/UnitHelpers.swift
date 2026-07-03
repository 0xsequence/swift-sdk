import Foundation

public enum UnitConversionError: Error, Equatable {
    case invalidDecimals(Int)
    case invalidValue(String)
    case fractionalComponentExceedsDecimals(value: String, decimals: Int)
}

public func parseUnits(value: String, decimals: Int = 18) throws -> String {
    try validate(decimals: decimals)

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let sign = parseSign(from: trimmedValue)
    let unsignedValue = sign.value

    guard !unsignedValue.isEmpty else {
        throw UnitConversionError.invalidValue(value)
    }

    let parts = unsignedValue.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2 else {
        throw UnitConversionError.invalidValue(value)
    }

    let wholePart = String(parts[0])
    let fractionalPart = parts.count == 2 ? String(parts[1]) : ""

    guard !wholePart.isEmpty || !fractionalPart.isEmpty else {
        throw UnitConversionError.invalidValue(value)
    }

    guard isDigits(wholePart) && isDigits(fractionalPart) else {
        throw UnitConversionError.invalidValue(value)
    }

    let rawValue = roundedRawValue(
        wholePart: wholePart,
        fractionalPart: fractionalPart,
        decimals: decimals
    )

    let normalizedRawValue = trimLeadingZeros(rawValue)
    guard normalizedRawValue != "0" else {
        return "0"
    }

    return sign.isNegative ? "-\(normalizedRawValue)" : normalizedRawValue
}

public func formatUnits(
    value: String,
    decimals: Int = 18
) throws -> String {
    try validate(decimals: decimals)

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let sign = parseSign(from: trimmedValue)
    let unsignedValue = sign.value

    guard !unsignedValue.isEmpty && isDigits(unsignedValue) else {
        throw UnitConversionError.invalidValue(value)
    }

    let normalizedValue = trimLeadingZeros(unsignedValue)
    guard normalizedValue != "0" else {
        return "0"
    }

    if decimals == 0 {
        return sign.isNegative ? "-\(normalizedValue)" : normalizedValue
    }

    let paddedValue = normalizedValue.count <= decimals
        ? String(repeating: "0", count: decimals - normalizedValue.count + 1) + normalizedValue
        : normalizedValue

    let splitIndex = paddedValue.index(paddedValue.endIndex, offsetBy: -decimals)
    let wholePart = String(paddedValue[..<splitIndex])
    var fractionalPart = String(paddedValue[splitIndex...])

    fractionalPart = String(fractionalPart.reversed().drop(while: { $0 == "0" }).reversed())

    let formattedValue = fractionalPart.isEmpty
        ? wholePart
        : "\(wholePart).\(fractionalPart)"

    return sign.isNegative ? "-\(formattedValue)" : formattedValue
}

private func validate(decimals: Int) throws {
    guard decimals >= 0 else {
        throw UnitConversionError.invalidDecimals(decimals)
    }
}

private func parseSign(from value: String) -> (isNegative: Bool, value: String) {
    guard let first = value.first else {
        return (false, value)
    }

    if first == "-" {
        return (true, String(value.dropFirst()))
    }

    if first == "+" {
        return (false, String(value.dropFirst()))
    }

    return (false, value)
}

private func roundedRawValue(
    wholePart: String,
    fractionalPart: String,
    decimals: Int
) -> String {
    let normalizedFractionalPart: String
    let shouldRound: Bool

    if fractionalPart.count > decimals {
        let roundingIndex = fractionalPart.index(fractionalPart.startIndex, offsetBy: decimals)
        normalizedFractionalPart = String(fractionalPart[..<roundingIndex])
        shouldRound = fractionalPart[roundingIndex] >= "5"
    } else {
        normalizedFractionalPart = fractionalPart
            + String(repeating: "0", count: decimals - fractionalPart.count)
        shouldRound = false
    }

    let rawValue = wholePart + normalizedFractionalPart
    return shouldRound ? incrementDecimalString(rawValue) : rawValue
}

private func isDigits(_ value: String) -> Bool {
    value.allSatisfy { $0 >= "0" && $0 <= "9" }
}

private func incrementDecimalString(_ value: String) -> String {
    var digits = Array(value.utf8)
    guard !digits.isEmpty else {
        return "1"
    }

    var index = digits.count - 1
    while true {
        if digits[index] == UInt8(ascii: "9") {
            digits[index] = UInt8(ascii: "0")
            if index == 0 {
                digits.insert(UInt8(ascii: "1"), at: 0)
                break
            }

            index -= 1
        } else {
            digits[index] += 1
            break
        }
    }

    return String(decoding: digits, as: UTF8.self)
}

private func trimLeadingZeros(_ value: String) -> String {
    let trimmedValue = value.drop(while: { $0 == "0" })
    return trimmedValue.isEmpty ? "0" : String(trimmedValue)
}
