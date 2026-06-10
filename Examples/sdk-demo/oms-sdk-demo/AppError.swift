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
        if error is CancellationError {
            return nil
        }
        self.message = errorMessage(for: error)
    }
}

private func errorMessage(for error: Error) -> String {
    if error is CancellationError {
        return "The operation was cancelled."
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

private func errorMessage(for error: WebRPCError) -> String {
    switch error.kind {
    case .answerIncorrect:
        return "The verification code is incorrect. Please try again."
    case .challengeExpired:
        return "The verification code expired. Request a new code and try again."
    case .commitmentConsumed:
        return "This verification code has already been used. Request a new code and try again."
    case .tooManyAttempts:
        return "Too many attempts. Please wait a moment before trying again."
    case .unauthorized:
        return "You are not authorized for this action. Please sign in again."
    case .unsupportedNetwork:
        return "The selected network is not supported."
    case .transactionFailed:
        return serviceErrorMessage(error, fallback: "The transaction failed.")
    case .walletProviderError:
        return serviceErrorMessage(error, fallback: "The wallet provider could not complete the request.")
    case .walletNotFound:
        return "Wallet not found. Please sign in again."
    case .invalidRequest, .webrpcBadRequest:
        return serviceErrorMessage(error, fallback: "The request was invalid.")
    case .webrpcBadResponse:
        return "The OMS service returned an unexpected response. Please try again."
    case .webrpcRequestFailed:
        return "The OMS request failed. Please check your connection and try again."
    case .internalError, .databaseError, .dataIntegrityError, .encryptionError, .webrpcInternalError, .webrpcServerPanic:
        return "The OMS service encountered an error. Please try again."
    default:
        return serviceErrorMessage(error, fallback: "An unexpected OMS error occurred.")
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

                    Text(message)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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
