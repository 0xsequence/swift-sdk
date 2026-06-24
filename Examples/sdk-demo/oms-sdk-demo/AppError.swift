import Foundation
import SwiftUI
import OMS_SDK

// MARK: - Errors

struct GenericAppError: Identifiable {
    let id = UUID()
    let message: String

    init(message: String) {
        self.message = message
    }

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

    if let error = error as? OmsSdkError {
        return errorMessage(for: error)
    }

    if let error = error as? WebRPCError {
        return errorMessage(for: error)
    }

    if let error = error as? WebRPCTransportError {
        if let underlyingDescription = error.underlyingDescription, !underlyingDescription.isEmpty {
            return "Unable to reach the OMS service. \(underlyingDescription)"
        }
        return "Unable to reach the OMS service. \(error.message)"
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

private func errorMessage(for error: OmsSdkError) -> String {
    var sections = [String]()
    sections.append(cleanPrimaryMessage(error.localizedDescription) ?? fallbackMessage(for: error))

    var details = [String]()
    if let operation = error.operation {
        details.append("Operation: \(operation.rawValue)")
    }
    details.append("SDK code: \(error.code.rawValue)")
    if let status = error.status {
        details.append("HTTP status: \(status)")
    }
    details.append("Retryable: \(error.retryable ? "yes" : "no")")

    if let webRPCError = webRPCError(from: error.underlyingError) {
        details.append(contentsOf: webRPCDetails(webRPCError))
    } else if let underlyingError = error.underlyingError {
        details.append("Underlying error: \(String(describing: underlyingError))")
    }

    if !details.isEmpty {
        sections.append(details.joined(separator: "\n"))
    }

    return sections.joined(separator: "\n\n")
}

private func errorMessage(for error: WebRPCError) -> String {
    let details = webRPCDetails(error).joined(separator: "\n")
    let diagnosticSuffix = details.isEmpty ? "" : "\n\n\(details)"

    switch error.kind {
    case .answerIncorrect:
        return "The verification code is incorrect. Please try again.\(diagnosticSuffix)"
    case .challengeExpired:
        return "The verification code expired. Request a new code and try again.\(diagnosticSuffix)"
    case .commitmentConsumed:
        return "This verification code has already been used. Request a new code and try again.\(diagnosticSuffix)"
    case .tooManyAttempts:
        return "Too many attempts. Please wait a moment before trying again.\(diagnosticSuffix)"
    case .unauthorized:
        return "You are not authorized for this action. Please sign in again.\(diagnosticSuffix)"
    case .unsupportedNetwork:
        return "The selected network is not supported.\(diagnosticSuffix)"
    case .transactionFailed:
        return serviceErrorMessage(error, fallback: "The transaction failed.") + diagnosticSuffix
    case .walletProviderError:
        return serviceErrorMessage(error, fallback: "The wallet provider could not complete the request.") + diagnosticSuffix
    case .walletNotFound:
        return "Wallet not found. Please sign in again.\(diagnosticSuffix)"
    case .invalidRequest, .webrpcBadRequest:
        return serviceErrorMessage(error, fallback: "The request was invalid.") + diagnosticSuffix
    case .webrpcBadResponse:
        return "The OMS service returned an unexpected response. Please try again.\(diagnosticSuffix)"
    case .webrpcRequestFailed:
        return "The OMS request failed. Please check your connection and try again.\(diagnosticSuffix)"
    case .internalError, .databaseError, .dataIntegrityError, .encryptionError, .webrpcInternalError, .webrpcServerPanic:
        return "The OMS service encountered an error. Please try again.\(diagnosticSuffix)"
    default:
        return serviceErrorMessage(error, fallback: "An unexpected OMS error occurred.") + diagnosticSuffix
    }
}

private func serviceErrorMessage(_ error: WebRPCError, fallback: String) -> String {
    let details = [error.message, error.cause]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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

private func fallbackMessage(for error: OmsSdkError) -> String {
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
        return "An OMS SDK operation failed."
    }
}

private func webRPCError(from error: (any Error)?) -> WebRPCError? {
    if let error = error as? WebRPCError {
        return error
    }
    if let error = error as? OmsSdkError {
        return webRPCError(from: error.underlyingError)
    }
    return nil
}

private func webRPCDetails(_ error: WebRPCError) -> [String] {
    var details = [
        "WebRPC error: \(error.error)",
        "WebRPC code: \(error.code)",
        "WebRPC kind: \(String(describing: error.kind))",
        "WebRPC status: \(error.status)"
    ]

    let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !message.isEmpty {
        details.append("WebRPC message: \(message)")
    }

    let cause = error.cause.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cause.isEmpty {
        details.append("WebRPC cause: \(cause)")
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
