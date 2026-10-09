import Foundation
import Testing
@testable import OMSWallet

private let ethereumAddress = "0x1111111111111111111111111111111111111111"
private let solanaAddress = "3gFktQX6vki5M2DzN8Y1ESPUJ4fJ8o6hVQWf8vYvPypD"
private let tronAddress = "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL"
private let typedData: JSONValue = .object(["primaryType": .string("Mail")])

enum SignatureVerificationMethod: CaseIterable, CustomTestStringConvertible {
    case evmMessage
    case evmTypedData
    case solanaMessage
    case tronMessage
    case tronTypedData

    var testDescription: String { "\(self)" }

    var walletType: WalletType {
        switch self {
        case .evmMessage, .evmTypedData: .ethereum
        case .solanaMessage: .solana
        case .tronMessage, .tronTypedData: .tron
        }
    }

    var address: String {
        switch walletType {
        case .ethereum: ethereumAddress
        case .solana: solanaAddress
        default: tronAddress
        }
    }

    var operation: OMSWalletOperation {
        switch self {
        case .evmMessage: .walletIsValidMessageSignature
        case .evmTypedData: .walletIsValidTypedDataSignature
        case .solanaMessage: .walletIsValidSolanaMessageSignature
        case .tronMessage: .walletIsValidTronMessageSignature
        case .tronTypedData: .walletIsValidTronTypedDataSignature
        }
    }

    var isTypedData: Bool {
        self == .evmTypedData || self == .tronTypedData
    }

    var path: String {
        isTypedData
            ? WaasPublicAPI.IsValidTypedDataSignature.urlPath
            : WaasPublicAPI.IsValidMessageSignature.urlPath
    }

    func enqueueValidResponse(_ transport: MockWaasTransport) throws {
        if isTypedData {
            try transport.enqueue(IsValidTypedDataSignatureResponse(isValid: true), for: path)
        } else {
            try transport.enqueue(IsValidMessageSignatureResponse(isValid: true), for: path)
        }
    }

    func call(_ client: WalletClient, walletAddress: String?) async throws -> Bool {
        switch self {
        case .evmMessage:
            try await client.isValidMessageSignature(
                network: .polygon,
                walletAddress: walletAddress,
                message: "hello",
                signature: "0xsig"
            )
        case .evmTypedData:
            try await client.isValidTypedDataSignature(
                network: .polygon,
                walletAddress: walletAddress,
                typedData: typedData,
                signature: "0xsig"
            )
        case .solanaMessage:
            try await client.isValidSolanaMessageSignature(
                walletAddress: walletAddress,
                message: "hello",
                signature: "0xsig"
            )
        case .tronMessage:
            try await client.isValidTronMessageSignature(
                walletAddress: walletAddress,
                message: "hello",
                signature: "0xsig"
            )
        case .tronTypedData:
            try await client.isValidTronTypedDataSignature(
                walletAddress: walletAddress,
                typedData: typedData,
                signature: "0xsig"
            )
        }
    }

    func expectedBody(walletAddress: String) -> NSDictionary {
        var body: [String: Any] = ["walletAddress": walletAddress, "signature": "0xsig"]
        switch self {
        case .evmMessage, .evmTypedData:
            body["network"] = "137"
            body["networkFamily"] = "evm"
        case .solanaMessage:
            body["networkFamily"] = "solana"
        case .tronMessage, .tronTypedData:
            body["networkFamily"] = "tron"
        }
        if isTypedData {
            body["typedData"] = ["primaryType": "Mail"]
        } else {
            body["message"] = "hello"
        }
        return body as NSDictionary
    }
}

private func activate(_ fixture: MockWalletClientFixture, type: WalletType, address: String) {
    fixture.client.activeWallet = Wallet(id: "wallet-active", type: type, address: address, keyOrigin: .enclave)
    fixture.client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    fixture.client.sessionAuth = .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
}

@Test(arguments: SignatureVerificationMethod.allCases)
func TestSignatureVerificationWithAddressWorksWhileSignedOut(_ method: SignatureVerificationMethod) async throws {
    let fixture = makeMockWalletClient()
    try method.enqueueValidResponse(fixture.transport)

    let isValid = try await method.call(fixture.client, walletAddress: method.address)

    let body = try fixture.transport.requestObject(for: method.path)
    #expect(isValid)
    #expect(body == method.expectedBody(walletAddress: method.address))
    #expect(body["walletId"] == nil)
}

@Test(arguments: SignatureVerificationMethod.allCases)
func TestSignatureVerificationWithAddressIgnoresActiveWalletType(_ method: SignatureVerificationMethod) async throws {
    let fixture = makeMockWalletClient()
    let otherType: WalletType = method.walletType == .solana ? .tron : .solana
    activate(fixture, type: otherType, address: otherType == .solana ? solanaAddress : tronAddress)
    try method.enqueueValidResponse(fixture.transport)

    _ = try await method.call(fixture.client, walletAddress: method.address)

    let body = try fixture.transport.requestObject(for: method.path)
    #expect(body == method.expectedBody(walletAddress: method.address))
}

@Test(arguments: SignatureVerificationMethod.allCases)
func TestSignatureVerificationWithoutAddressUsesActiveWalletAddress(_ method: SignatureVerificationMethod) async throws {
    let fixture = makeMockWalletClient()
    activate(fixture, type: method.walletType, address: method.address)
    try method.enqueueValidResponse(fixture.transport)

    let isValid = try await method.call(fixture.client, walletAddress: nil)

    let body = try fixture.transport.requestObject(for: method.path)
    #expect(isValid)
    #expect(body == method.expectedBody(walletAddress: method.address))
    #expect(body["walletId"] == nil)
}

@Test(arguments: SignatureVerificationMethod.allCases)
func TestSignatureVerificationWithoutAddressRequiresSession(_ method: SignatureVerificationMethod) async throws {
    let fixture = makeMockWalletClient()

    do {
        _ = try await method.call(fixture.client, walletAddress: nil)
        Issue.record("Expected a missing-session error")
    } catch let error as OMSWalletError {
        #expect(error.code == .sessionMissing)
        #expect(error.operation == method.operation)
    }
    #expect(fixture.transport.requestCount(for: method.path) == 0)
}

@Test(arguments: SignatureVerificationMethod.allCases)
func TestSignatureVerificationWithoutAddressRejectsMismatchedActiveWallet(
    _ method: SignatureVerificationMethod
) async throws {
    let fixture = makeMockWalletClient()
    let otherType: WalletType = method.walletType == .ethereum ? .solana : .ethereum
    activate(fixture, type: otherType, address: otherType == .ethereum ? ethereumAddress : solanaAddress)

    do {
        _ = try await method.call(fixture.client, walletAddress: nil)
        Issue.record("Expected a validation error")
    } catch let error as OMSWalletError {
        #expect(error.code == .validationError)
        #expect(error.operation == method.operation)
    }
    #expect(fixture.transport.requestCount(for: method.path) == 0)
}

@Test(arguments: SignatureVerificationMethod.allCases, ["", "  "])
func TestSignatureVerificationRejectsBlankAddress(
    _ method: SignatureVerificationMethod,
    walletAddress: String
) async throws {
    let fixture = makeMockWalletClient()
    activate(fixture, type: method.walletType, address: method.address)
    try method.enqueueValidResponse(fixture.transport)

    do {
        _ = try await method.call(fixture.client, walletAddress: walletAddress)
        Issue.record("Expected a validation error")
    } catch let error as OMSWalletError {
        #expect(error.code == .validationError)
        #expect(error.operation == method.operation)
        #expect(error.localizedDescription == "walletAddress must not be empty")
    }
    #expect(fixture.transport.requestCount(for: method.path) == 0)
}
