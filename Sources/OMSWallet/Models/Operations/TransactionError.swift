import Foundation

public enum TransactionError: Error {
    case noFeeOptionsAvailable
    case noFeeOptionSelected
    case missingTransactionHash
    case transactionFailed(status: TransactionStatus)
    case pollingTimedOut
}

extension TransactionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noFeeOptionsAvailable:
            return "No fee options are available for this transaction."
        case .noFeeOptionSelected:
            return "No fee option was selected for this transaction."
        case .missingTransactionHash:
            return "Transaction status response is missing a transaction hash."
        case .transactionFailed(let status):
            return "Transaction failed with status: \(status)."
        case .pollingTimedOut:
            return "Transaction polling timed out."
        }
    }
}
