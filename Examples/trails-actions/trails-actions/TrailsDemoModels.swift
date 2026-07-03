import Foundation
import OMSWallet

let trailsAPIURL = "https://trails-api.sequence.app"
let trailsRedirectURI = "omsclienttrailsdemo://auth/callback"
let defaultPublishableKey = "pk_sdbx_01kqfw9zaykks_01kwetq606fv699qb9bhfmb45s"
let trailsAccessKey = "AQAAAAAAAMDoWz-avqIIjXGH7JJlBSormpo"
let trailsAccessKeyHeader = "X-Access-Key"

let polygonNetwork: Network = .polygon
let polygonChainID = 137
let polygonUSDC = "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359"
let polygonNativeTokenAddress = "0x0000000000000000000000000000000000000000"

let defaultSwapPOLAmount = "0.5"
let defaultDepositUSDCAmount = "0.1"
let defaultEarnPOLAmount = "1"
let noEarnPositionsStatus = "No deposited earn positions."
let postSendRefreshAttempts = 24
let postSendRefreshDelayNanoseconds: UInt64 = 2_500_000_000

struct TrailsDemoError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    static let invalidAuthorizationURL = TrailsDemoError(message: "The authorization URL could not be opened.")
    static let missingWallet = TrailsDemoError(message: "Sign in before preparing a Trails action.")
    static let missingPreparedTransaction = TrailsDemoError(message: "Prepare the transaction first.")
    static let missingYieldTransaction = TrailsDemoError(message: "Yield action did not return a transaction.")
    static let incompleteYieldTransaction = TrailsDemoError(message: "Yield action returned an incomplete transaction.")
    static let unsupportedYieldTransaction = TrailsDemoError(message: "This demo only sends Polygon transactions.")
}

struct AppError: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: Error) {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            self.message = description
        } else {
            self.message = String(describing: error)
        }
    }
}

struct SafariAuthSession: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
final class FeeOptionSelectionRequest: Identifiable {
    let id = UUID()
    let options: [FeeOptionWithBalance]

    private var continuation: CheckedContinuation<FeeOptionSelection?, Error>?

    init(
        options: [FeeOptionWithBalance],
        continuation: CheckedContinuation<FeeOptionSelection?, Error>
    ) {
        self.options = options
        self.continuation = continuation
    }

    var isResolved: Bool {
        continuation == nil
    }

    func select(_ option: FeeOptionWithBalance) {
        resume(returning: option.selection)
    }

    func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }

    private func resume(returning selection: FeeOptionSelection?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selection)
    }
}

enum AuthStep {
    case email
    case code
}

struct BalanceState: Equatable {
    let pol: String
    let usdc: String
    let polRaw: String
    let usdcRaw: String
    let status: String

    static let signedOut = BalanceState(
        pol: "-",
        usdc: "-",
        polRaw: "0",
        usdcRaw: "0",
        status: "Sign in to load balances."
    )
}

struct EarnPosition: Identifiable, Equatable {
    let id: String
    let marketID: String
    let marketName: String
    let provider: String
    let amount: String
    let amountDisplay: String
    let amountRaw: String
    let amountUSD: String?
    let apy: String
    let tokenSymbol: String
    let outputToken: String
    let outputTokenNetwork: String
    let canWithdraw: Bool
}

struct ParsedYieldTransaction: Identifiable, Equatable {
    let id = UUID()
    let to: String
    let data: String
    let value: String
    let chainID: Int

    var request: SendTransactionRequest {
        SendTransactionRequest(to: to, value: value, data: data)
    }
}

enum PostSendExpectation: Equatable {
    case usdcIncrease(minIncreaseRaw: String)
    case earnMarketIncrease(marketID: String)
    case earnMarketDecrease(marketID: String)
}

final class PreparedSwapExecutionState {
    var submittedResponse: SendTransactionResponse?
    var selectedFeeOption: FeeOptionWithBalance?
    var committedIntentID: String?
    var didExecuteIntent = false
}

final class PreparedYieldExecutionState {
    private var submittedResponses: [SendTransactionResponse?] = []

    func submittedResponse(at index: Int) -> SendTransactionResponse? {
        guard submittedResponses.indices.contains(index) else { return nil }
        return submittedResponses[index]
    }

    func recordSubmittedResponse(_ response: SendTransactionResponse, at index: Int) {
        ensureCapacity(for: index)
        submittedResponses[index] = response
    }

    private func ensureCapacity(for index: Int) {
        guard index >= submittedResponses.count else { return }
        submittedResponses.append(contentsOf: Array(repeating: nil, count: index - submittedResponses.count + 1))
    }
}

struct PreparedSwapTransaction: Identifiable {
    let id = UUID()
    let title: String
    let request: SendTransactionRequest
    let intent: WebRPCJSONValue
    let outputRaw: String
    let outputDisplay: String
    let postSendExpectation: PostSendExpectation
    let marketName: String?
    let marketID: String?
    let executionState = PreparedSwapExecutionState()
}

struct PreparedYieldTransactions: Identifiable {
    let id = UUID()
    let title: String
    let transactions: [ParsedYieldTransaction]
    let postSendExpectation: PostSendExpectation
    let marketName: String?
    let marketID: String?
    let executionState = PreparedYieldExecutionState()
}

final class PreparedSwapAndEarnExecutionState {
    var preparedDeposit: PreparedYieldTransactions?
}

struct PreparedSwapAndEarnPlan: Identifiable {
    let id = UUID()
    let swap: PreparedSwapTransaction
    let market: YieldMarket
    let depositAmount: String
    let executionState = PreparedSwapAndEarnExecutionState()
}

struct TransactionResultViewState: Identifiable, Equatable {
    let id = UUID()
    let value: String
    let explorerURL: URL?

    init(_ response: SendTransactionResponse) {
        let value = response.txnHash ?? response.txnId
        self.value = value
        if let hash = response.txnHash {
            self.explorerURL = URL(string: "\(polygonNetwork.explorerUrl)/tx/\(hash)")
        } else {
            self.explorerURL = nil
        }
    }
}

struct SignedInDataRefresh {
    let balances: BalanceState?
    let positions: [EarnPosition]?
}

func normalizeAmountInput(_ value: String) -> String? {
    let normalizedSeparator = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
    var decimalCount = 0

    for character in normalizedSeparator {
        if character >= "0" && character <= "9" {
            continue
        }
        if character == "." {
            decimalCount += 1
            guard decimalCount <= 1 else { return nil }
            continue
        }
        return nil
    }

    return normalizedSeparator.first == "." ? "0\(normalizedSeparator)" : normalizedSeparator
}

func parsePositiveAmount(_ value: String, decimals: Int, label: String) throws -> String {
    let normalized = try requireNormalizedAmountInput(value, label: label)
    guard !normalized.isEmpty else {
        throw TrailsDemoError(message: "Enter a \(label) amount.")
    }

    let raw = try parseUnits(value: normalized, decimals: decimals)
    guard normalizedUnsignedInteger(raw) != "0" else {
        throw TrailsDemoError(message: "Enter a \(label) amount greater than zero.")
    }

    return raw
}

func requireNormalizedAmountInput(_ value: String, label: String) throws -> String {
    guard let normalized = normalizeAmountInput(value) else {
        throw TrailsDemoError(message: "Enter a valid \(label) amount.")
    }
    return normalized
}

func formatTokenAmount(_ rawBalance: String?, decimals: Int, symbol: String) -> String {
    guard let rawBalance, !rawBalance.isEmpty else {
        return "0 \(symbol)"
    }

    do {
        let formatted = try formatUnits(value: rawBalance, decimals: decimals)
        return "\(trimFraction(formatted, maxFractionDigits: 6)) \(symbol)"
    } catch {
        return "- \(symbol)"
    }
}

func formatDisplayAmount(_ amount: String, maxFractionDigits: Int = 4) -> String {
    trimFraction(amount, maxFractionDigits: maxFractionDigits)
}

func trimFraction(_ value: String, maxFractionDigits: Int) -> String {
    guard maxFractionDigits > 0 else {
        return String(value.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
    }

    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return value }

    let whole = parts[0].isEmpty ? "0" : String(parts[0])
    let limitedFraction = String(parts[1].prefix(maxFractionDigits))
    let trimmedFraction = String(limitedFraction.reversed().drop(while: { $0 == "0" }).reversed())
    return trimmedFraction.isEmpty ? whole : "\(whole).\(trimmedFraction)"
}

func formatUSD(_ value: String?) -> String? {
    guard let value, let amount = Double(value), amount.isFinite else {
        return nil
    }

    return amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
}

func formatAPY(_ rewardRate: YieldRewardRate?) -> String {
    guard let total = rewardRate?.total,
          total.isFinite,
          total >= 0,
          total <= 0.5 else {
        return "-"
    }

    let percent = total * 100
    return "\(percent.formatted(.number.precision(.fractionLength(percent >= 10 ? 1 : 2))))%"
}

func shortHash(_ value: String) -> String {
    guard value.count > 18 else { return value }
    return "\(value.prefix(10))...\(value.suffix(8))"
}

func collapsedAddress(_ value: String) -> String {
    guard value.count > 14 else { return value }
    return "\(value.prefix(6))...\(value.suffix(4))"
}

func formatSessionDate(_ date: Date?) -> String {
    guard let date else { return "Unknown" }
    return date.formatted(date: .abbreviated, time: .shortened)
}

func normalizedUnsignedInteger(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          trimmed.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
        return nil
    }

    let stripped = trimmed.drop(while: { $0 == "0" })
    return stripped.isEmpty ? "0" : String(stripped)
}

func compareUnsignedInteger(_ lhs: String?, _ rhs: String?) -> ComparisonResult? {
    guard let lhs = normalizedUnsignedInteger(lhs),
          let rhs = normalizedUnsignedInteger(rhs) else {
        return nil
    }

    if lhs.count != rhs.count {
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }

    if lhs == rhs {
        return .orderedSame
    }

    return lhs < rhs ? .orderedAscending : .orderedDescending
}

func addUnsignedIntegers(_ lhs: String, _ rhs: String) -> String {
    let left = Array(normalizedUnsignedInteger(lhs) ?? "0").reversed()
    let right = Array(normalizedUnsignedInteger(rhs) ?? "0").reversed()
    let maxCount = max(left.count, right.count)
    let leftDigits = Array(left)
    let rightDigits = Array(right)
    var carry = 0
    var result: [String] = []

    for index in 0..<maxCount {
        let leftDigit = index < leftDigits.count ? Int(String(leftDigits[index])) ?? 0 : 0
        let rightDigit = index < rightDigits.count ? Int(String(rightDigits[index])) ?? 0 : 0
        let sum = leftDigit + rightDigit + carry
        result.append(String(sum % 10))
        carry = sum / 10
    }

    if carry > 0 {
        result.append(String(carry))
    }

    return String(result.reversed().joined().drop(while: { $0 == "0" })).nonEmpty ?? "0"
}

func subtractUnsignedIntegers(_ lhs: String, _ rhs: String) -> String? {
    guard compareUnsignedInteger(lhs, rhs) != .orderedAscending else {
        return nil
    }

    let leftDigits = Array((normalizedUnsignedInteger(lhs) ?? "0").reversed())
    let rightDigits = Array((normalizedUnsignedInteger(rhs) ?? "0").reversed())
    var borrow = 0
    var result: [String] = []

    for index in 0..<leftDigits.count {
        var leftDigit = (Int(String(leftDigits[index])) ?? 0) - borrow
        let rightDigit = index < rightDigits.count ? Int(String(rightDigits[index])) ?? 0 : 0
        if leftDigit < rightDigit {
            leftDigit += 10
            borrow = 1
        } else {
            borrow = 0
        }
        result.append(String(leftDigit - rightDigit))
    }

    return String(result.reversed().joined().drop(while: { $0 == "0" })).nonEmpty ?? "0"
}

func hasEnoughBalance(_ option: FeeOptionWithBalance) -> Bool {
    compareUnsignedInteger(option.availableRaw, option.feeOption.value).map { $0 != .orderedAscending } ?? false
}

func feeTokenLabel(_ option: FeeOptionWithBalance) -> String {
    let symbol = option.feeOption.token.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    if !symbol.isEmpty {
        return symbol
    }

    let name = option.feeOption.token.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty {
        return name
    }

    return option.feeOption.token.tokenId ?? "Unknown token"
}

func feeAmountLabel(_ option: FeeOptionWithBalance) -> String {
    let displayValue = option.feeOption.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return displayValue.isEmpty ? option.feeOption.value : displayValue
}

func parseUnsignedYieldTransaction(_ value: WebRPCJSONValue?) throws -> ParsedYieldTransaction {
    guard let value else {
        throw TrailsDemoError.incompleteYieldTransaction
    }

    if case .string(let rawJSON) = value,
       rawJSON.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
       let data = rawJSON.data(using: .utf8) {
        return try parseUnsignedYieldTransaction(try JSONDecoder().decode(WebRPCJSONValue.self, from: data))
    }

    guard case .object(let object) = value else {
        throw TrailsDemoError.incompleteYieldTransaction
    }

    guard let to = jsonString(object["to"]),
          let chainID = jsonInt(object["chainId"]) else {
        throw TrailsDemoError.incompleteYieldTransaction
    }

    return ParsedYieldTransaction(
        to: to,
        data: jsonString(object["data"]) ?? "0x",
        value: jsonString(object["value"]) ?? "0",
        chainID: chainID
    )
}

func jsonString(_ value: WebRPCJSONValue?) -> String? {
    switch value {
    case .string(let string):
        return string
    case .integer(let integer):
        return String(integer)
    case .unsignedInteger(let integer):
        return String(integer)
    case .number(let number):
        guard number.isFinite else { return nil }
        if number.rounded(.towardZero) == number {
            return String(Int64(number))
        }
        return String(number)
    case .bool(let bool):
        return bool ? "true" : "false"
    case .object, .array, .null, .none:
        return nil
    }
}

func jsonInt(_ value: WebRPCJSONValue?) -> Int? {
    switch value {
    case .integer(let integer):
        return Int(integer)
    case .unsignedInteger(let integer):
        return Int(integer)
    case .number(let number):
        return number.isFinite ? Int(number) : nil
    case .string(let string):
        return Int(string)
    case .object, .array, .bool, .null, .none:
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
