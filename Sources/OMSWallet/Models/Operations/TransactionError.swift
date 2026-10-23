import Foundation

enum TransactionError: Error {
    case noFeeOptionsAvailable
    case noFeeOptionSelected
    case transactionFailed(status: TransactionStatus)
    case invalidPollingOption(String)
}

extension TransactionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noFeeOptionsAvailable:
            return "No fee options are available for this transaction."
        case .noFeeOptionSelected:
            return "No fee option was selected for this transaction."
        case .transactionFailed(let status):
            return "Transaction failed with status: \(status)."
        case .invalidPollingOption(let message):
            return message
        }
    }
}
