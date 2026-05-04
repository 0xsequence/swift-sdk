import Foundation

public enum UnitConversionError: Error, Equatable {
    case invalidDecimals(Int)
    case invalidValue(String)
    case fractionalComponentExceedsDecimals(value: String, decimals: Int)
}

public final class OMSClientUtils {
    init() {}

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

        let normalizedFractionalPart = try normalizeFractionalPart(
            fractionalPart,
            decimals: decimals,
            originalValue: value
        )

        let rawValue = trimLeadingZeros(wholePart + normalizedFractionalPart)
        guard rawValue != "0" else {
            return "0"
        }

        return sign.isNegative ? "-\(rawValue)" : rawValue
    }

    public func formatUnits(
        value: String,
        decimals: Int = 18,
        trimTrailingZeros: Bool = true
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

        if trimTrailingZeros {
            fractionalPart = String(fractionalPart.reversed().drop(while: { $0 == "0" }).reversed())
        }

        let formattedValue = fractionalPart.isEmpty
            ? wholePart
            : "\(wholePart).\(fractionalPart)"

        return sign.isNegative ? "-\(formattedValue)" : formattedValue
    }

    public func parseEther(value: String) throws -> String {
        try parseUnits(value: value, decimals: 18)
    }

    public func formatEther(
        value: String,
        trimTrailingZeros: Bool = true
    ) throws -> String {
        try formatUnits(value: value, decimals: 18, trimTrailingZeros: trimTrailingZeros)
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

    private func normalizeFractionalPart(
        _ fractionalPart: String,
        decimals: Int,
        originalValue: String
    ) throws -> String {
        if fractionalPart.count > decimals {
            let allowedEndIndex = fractionalPart.index(fractionalPart.startIndex, offsetBy: decimals)
            let extraFractionalPart = fractionalPart[allowedEndIndex...]

            guard extraFractionalPart.allSatisfy({ $0 == "0" }) else {
                throw UnitConversionError.fractionalComponentExceedsDecimals(
                    value: originalValue,
                    decimals: decimals
                )
            }

            return String(fractionalPart[..<allowedEndIndex])
        }

        return fractionalPart + String(repeating: "0", count: decimals - fractionalPart.count)
    }

    private func isDigits(_ value: String) -> Bool {
        value.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private func trimLeadingZeros(_ value: String) -> String {
        let trimmedValue = value.drop(while: { $0 == "0" })
        return trimmedValue.isEmpty ? "0" : String(trimmedValue)
    }
}
