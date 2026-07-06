import Foundation
import SwiftUI
import OMSWallet

// MARK: - Errors

struct GenericAppError: Identifiable {
    let id = UUID()
    let message: String

    init?(_ error: Error) {
        if isCancellation(error) {
            return nil
        }
        self.message = errorMessage(for: error)
    }
}

private func errorMessage(for error: Error) -> String {
    if isCancellation(error) {
        return "The operation was cancelled."
    }

    if let error = error as? OMSWalletError {
        return errorMessage(for: error)
    }

    if let error = error as? TransactionError {
        switch error {
        case .noFeeOptionsAvailable:
            return "No fee options are available for this transaction."
        case .noFeeOptionSelected:
            return "Select a fee option to continue."
        case .missingTransactionHash:
            return "The transaction was submitted, but no transaction hash was returned."
        case .transactionFailed(let status):
            return "The transaction failed with status \(status)."
        case .pollingTimedOut:
            return "The transaction is taking longer than expected. Check the wallet activity and try again."
        }
    }

    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
        return description
    }

    let description = String(describing: error)
    return description.isEmpty
        ? "An unexpected error occurred. Please try again."
        : description
}

private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError {
        return urlError.code == .cancelled
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}

private func errorMessage(for error: OMSWalletError) -> String {
    var sections = [String]()
    sections.append(primaryMessage(for: error))

    var details = [String]()
    if let operation = error.operation {
        details.append("Operation: \(operation.rawValue)")
    }
    details.append("SDK code: \(error.code.rawValue)")
    if let status = error.status {
        details.append("HTTP status: \(status)")
    }
    details.append("Retryable: \(retryableDescription(error.retryable))")

    if let upstreamError = error.upstreamError {
        details.append(contentsOf: upstreamDetails(upstreamError))
    }

    if let underlyingError = error.underlyingError {
        details.append("Underlying error: \(String(describing: underlyingError))")
    }

    if !details.isEmpty {
        sections.append(details.joined(separator: "\n"))
    }

    return sections.joined(separator: "\n\n")
}

private func primaryMessage(for error: OMSWalletError) -> String {
    if let message = waasMessage(for: error) {
        return message
    }
    return cleanPrimaryMessage(error.localizedDescription) ?? fallbackMessage(for: error)
}

private func retryableDescription(_ retryable: Bool?) -> String {
    switch retryable {
    case .some(true):
        return "yes"
    case .some(false):
        return "no"
    case nil:
        return "not specified"
    }
}

private func waasMessage(for error: OMSWalletError) -> String? {
    guard let upstreamError = error.upstreamError, upstreamError.service == .waas else {
        return nil
    }

    switch upstreamKey(upstreamError) {
    case "7003", "answerincorrect":
        return "The verification code is incorrect. Please try again."
    case "7004", "challengeexpired":
        return "The verification code expired. Request a new code and try again."
    case "7008", "commitmentconsumed":
        return "This verification code has already been used. Request a new code and try again."
    case "7005", "toomanyattempts":
        return "Too many attempts. Please wait a moment before trying again."
    case "7207", "unauthorized":
        return "You are not authorized for this action. Please sign in again."
    case "7304", "unsupportednetwork":
        return "The selected network is not supported."
    case "7306", "transactionfailed":
        return serviceErrorMessage(upstreamError, fallback: "The transaction failed.")
    case "7307", "walletprovidererror":
        return serviceErrorMessage(upstreamError, fallback: "The wallet provider could not complete the request.")
    case "7300", "walletnotfound":
        return "Wallet not found. Please sign in again."
    case "7200", "invalidrequest", "-4", "webrpcbadrequest":
        return serviceErrorMessage(upstreamError, fallback: "The request was invalid.")
    case "-5", "webrpcbadresponse":
        return "The OMS service returned an unexpected response. Please try again."
    case "-1", "webrpcrequestfailed":
        return "The OMS request failed. Please check your connection and try again."
    case "7100", "7101", "7102", "7103", "-6", "-7",
         "internalerror", "databaseerror", "dataintegrityerror", "encryptionerror",
         "webrpcinternalerror", "webrpcserverpanic":
        return "The OMS service encountered an error. Please try again."
    default:
        return nil
    }
}

private func upstreamKey(_ error: OMSWalletUpstreamError) -> String {
    if let code = error.code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
        return code
    }
    return error.name?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .lowercased() ?? ""
}

private func serviceErrorMessage(_ error: OMSWalletUpstreamError, fallback: String) -> String {
    let details = [error.message]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0 != "endpoint error" && $0 != "bad response" }

    guard let detail = details.first else {
        return fallback
    }

    return "\(fallback) \(detail)"
}

private func cleanPrimaryMessage(_ message: String) -> String? {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    if trimmed == "endpoint error" || trimmed == "bad response" {
        return nil
    }
    return trimmed
}

private func fallbackMessage(for error: OMSWalletError) -> String {
    switch error.code {
    case .httpError:
        return "The OMS service returned an HTTP error."
    case .invalidResponse:
        return "The OMS service returned an unexpected response."
    case .requestFailed:
        return "The OMS request failed."
    case .validationError:
        return "The request was invalid."
    case .sessionMissing, .sessionExpired:
        return error.localizedDescription
    default:
        return "An OMS Wallet operation failed."
    }
}

private func upstreamDetails(_ error: OMSWalletUpstreamError) -> [String] {
    var details = ["Upstream service: \(error.service.rawValue)"]

    if let name = error.name, !name.isEmpty {
        details.append("Upstream error: \(name)")
    }
    if let code = error.code, !code.isEmpty {
        details.append("Upstream code: \(code)")
    }
    if let message = error.message, !message.isEmpty {
        details.append("Upstream message: \(message)")
    }
    if let status = error.status {
        details.append("Upstream status: \(status)")
    }

    return details
}

extension View {
    func genericErrorWindow(error: Binding<GenericAppError?>) -> some View {
        modifier(GenericErrorDialog(error: error))
    }
}

private struct GenericErrorDialog: ViewModifier {
    @Binding var error: GenericAppError?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let error {
                    TokenDialog(
                        title: "Something went wrong",
                        message: error.message,
                        primaryTitle: "OK",
                        primaryAction: {
                            self.error = nil
                        }
                    )
                }
            }
    }
}

struct TokenDialog: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            DesignTokens.Color.primaryText
                .opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(DesignTokens.Typography.heading)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        Text(message)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 260, alignment: .leading)
                }

                HStack(spacing: 12) {
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(DesignButtonStyle(variant: .secondary))
                    }

                    Spacer(minLength: 0)

                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(DesignButtonStyle(variant: .primary))
                }
            }
            .padding(24)
            .frame(maxWidth: 360, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(DesignTokens.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Color.headerBorder, lineWidth: DesignTokens.Stroke.defaultWidth)
            )
            .padding(24)
        }
    }
}
