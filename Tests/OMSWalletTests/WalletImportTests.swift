import CryptoKit
import Foundation
import Testing
@testable import OMSWallet

@Test func TestWalletImportPrivateKeyValidationCoversScalarAndLengthBoundaries() throws {
    let one = Data(repeating: 0, count: 31) + Data([1])
    let tronKey = String(repeating: "11", count: 32)
    #expect(try WalletImportValidation.plaintext(.ethereumBytes(one)) == one)
    #expect(try WalletImportValidation.plaintext(.tronBytes(one)) == one)
    #expect(try WalletImportValidation.plaintext(.tron(" 0x\(tronKey)\n")) == Data("0x\(tronKey)".utf8))
    #expect(try WalletImportValidation.plaintext(.tron(tronKey)) == Data(tronKey.utf8))
    #expect(try WalletImportValidation.plaintext(.solanaBytes(Data(repeating: 7, count: 64))).count == 64)

    let secp256k1Order = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
    let cases: [(WalletImportPrivateKey, String)] = [
        (.ethereum("0x1234"), "Ethereum privateKey must be 32 bytes or 64 hexadecimal characters"),
        (.ethereumBytes(Data(repeating: 0, count: 32)), "Ethereum privateKey is outside the valid secp256k1 scalar range"),
        (.ethereum(secp256k1Order), "Ethereum privateKey is outside the valid secp256k1 scalar range"),
        (.tron("0x1234"), "Tron privateKey must be 32 bytes or 64 hexadecimal characters"),
        (.tronBytes(Data(repeating: 1, count: 31)), "Tron privateKey must contain exactly 32 bytes"),
        (.tronBytes(Data(repeating: 0, count: 32)), "Tron privateKey is outside the valid secp256k1 scalar range"),
        (.tron(secp256k1Order), "Tron privateKey is outside the valid secp256k1 scalar range"),
        (
            .solanaBytes(Data(repeating: 7, count: 31)),
            "Solana privateKey must contain a 32-byte seed or 64-byte keypair"
        ),
        (
            .solana(String(repeating: "1", count: 32)),
            "Solana privateKey string is ambiguous; provide the raw bytes instead"
        ),
    ]
    for (privateKey, message) in cases {
        do {
            _ = try WalletImportValidation.plaintext(privateKey)
            Issue.record("Expected \(message)")
        } catch let error as OMSWalletError {
            #expect(error.code == .validationError)
            #expect(error.localizedDescription == message)
        }
    }

    do {
        try WalletImportValidation.validateReference(String(repeating: "é", count: 65))
        Issue.record("Expected an oversized reference to be rejected")
    } catch let error as OMSWalletError {
        #expect(error.code == .validationError)
        #expect(error.localizedDescription == "reference must be at most 128 UTF-8 bytes")
    }
}

@Test func TestWalletMappingPreservesUnknownKeyOrigin() throws {
    let wallet = try Wallet(
        waasValue: WaasGenerated.Wallet(
            id: "wallet-id",
            networkFamily: .evm,
            keyOrigin: .unknown("future-origin"),
            address: "0x1111111111111111111111111111111111111111"
        )
    )
    let futureNetworkWallet = try Wallet(
        waasValue: WaasGenerated.Wallet(
            id: "future-wallet-id",
            networkFamily: .unknown("future-network"),
            keyOrigin: .enclave,
            address: "future-address"
        )
    )

    #expect(wallet.keyOrigin == .unknown("future-origin"))
    #expect(futureNetworkWallet.type == .unknown("future-network"))
}

@Test func TestAttestationVerifierRejectsUntrustedOrMismatchedDocuments() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let trustedPcr0 = Data(repeating: 0xaa, count: 48)
    let trustedPcr0s = Set([trustedPcr0.map { String(format: "%02x", $0) }.joined()])
    let requestBody = "{}"
    let responseBody = #"{"keyId":"key-id"}"#
    let nonce = "test-nonce"

    expectAttestationFailure("invalid COSE_Sign1 structure") {
        try AttestationVerifier.verify(
            encodedDocument: Data([0]).base64EncodedString(),
            method: "POST",
            path: "/v1/Waas/GetRecipientKey",
            requestSignature: "",
            requestBody: requestBody,
            responseBody: responseBody,
            nonce: nonce,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("freshness window") {
        try verifySyntheticAttestation(
            timestamp: now.addingTimeInterval(-6 * 60),
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("PCR0 is not trusted") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: Data(repeating: 0xbb, count: 48),
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
    expectAttestationFailure("nonce does not match") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now,
            verificationNonce: "different-nonce"
        )
    }
    expectAttestationFailure("not bound to the request and response") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now,
            verificationResponseBody: "{}"
        )
    }
    expectAttestationFailure("does not use the AWS Nitro root") {
        try verifySyntheticAttestation(
            timestamp: now,
            pcr0: trustedPcr0,
            nonce: nonce,
            requestBody: requestBody,
            responseBody: responseBody,
            trustedPcr0s: trustedPcr0s,
            now: now
        )
    }
}

private func verifySyntheticAttestation(
    timestamp: Date,
    pcr0: Data,
    nonce: String,
    requestBody: String,
    responseBody: String,
    trustedPcr0s: Set<String>,
    now: Date,
    verificationNonce: String? = nil,
    verificationResponseBody: String? = nil
) throws {
    let method = "POST"
    let path = "/v1/Waas/GetRecipientKey"
    let preimage = "\(method) \(path)\n\(requestBody)\n\(responseBody)"
    try AttestationVerifier.verify(
        encodedDocument: try syntheticAttestationDocument(
            timestamp: timestamp,
            pcr0: pcr0,
            nonce: nonce,
            userData: attestationUserData("Sequence/1", preimage)
        ),
        method: method,
        path: path,
        requestSignature: "",
        requestBody: requestBody,
        responseBody: verificationResponseBody ?? responseBody,
        nonce: verificationNonce ?? nonce,
        trustedPcr0s: trustedPcr0s,
        now: now
    )
}

private func attestationUserData(_ prefix: String, _ preimage: String) -> Data {
    Data("\(prefix):\(Data(SHA256.hash(data: Data(preimage.utf8))).base64EncodedString())".utf8)
}

private func syntheticAttestationDocument(
    timestamp: Date,
    pcr0: Data,
    nonce: String,
    userData: Data
) throws -> String {
    let protectedHeader = try AttestationCBOR.encode(.map([
        (.unsigned(1), .negative(34))
    ]))
    let payload = try AttestationCBOR.encode(.map([
        (.textString("digest"), .textString("SHA384")),
        (.textString("timestamp"), .unsigned(UInt64(timestamp.timeIntervalSince1970 * 1_000))),
        (.textString("pcrs"), .map([(.unsigned(0), .byteString(pcr0))])),
        (.textString("certificate"), .byteString(Data([1]))),
        (.textString("cabundle"), .array([.byteString(Data([2]))])),
        (.textString("user_data"), .byteString(userData)),
        (.textString("nonce"), .byteString(Data(nonce.utf8)))
    ]))
    let document = AttestationCBOR.Value.tagged(
        18,
        .array([
            .byteString(protectedHeader),
            .map([]),
            .byteString(payload),
            .byteString(Data(repeating: 0, count: 96))
        ])
    )
    return try AttestationCBOR.encode(document).base64EncodedString()
}

@Test func TestAttestationUserDataVersion2BindsTheRequestSignatureHeader() throws {
    let method = "POST"
    let path = "/v1/Waas/CommitVerifier"
    let requestBody = #"{"identityType":"Email"}"#
    let responseBody = #"{"verifier":"verifier"}"#
    let signature = "alg=ecdsa-p256-sha256;scope=proj;cred=cred-id;nonce=1;sig=signed"
    let request = "\(method) \(path)\n"
    func version(_ userData: Data, signature: String) throws -> Int {
        try AttestationVerifier.userDataVersion(
            userData,
            method: method,
            path: path,
            requestSignature: signature,
            requestBody: requestBody,
            responseBody: responseBody
        )
    }
    let version1 = attestationUserData("Sequence/1", request + "\(requestBody)\n\(responseBody)")
    let version2 = attestationUserData("Sequence/2", request + "\(signature)\n\(requestBody)\n\(responseBody)")
    let unsignedVersion2 = attestationUserData("Sequence/2", request + "\n\(requestBody)\n\(responseBody)")

    #expect(try version(version1, signature: signature) == 1)
    #expect(try version(version2, signature: signature) == 2)
    #expect(try version(unsignedVersion2, signature: "") == 2)
    expectAttestationFailure("not bound to the request and response") {
        _ = try version(version2, signature: "alg=ecdsa-p256-sha256;scope=proj;cred=edge-cred;nonce=1;sig=edge")
    }
    expectAttestationFailure("not bound to the request and response") {
        _ = try version(unsignedVersion2, signature: signature)
    }
    expectAttestationFailure("unsupported version") {
        _ = try version(attestationUserData("Sequence/3", request + "\(requestBody)\n\(responseBody)"), signature: "")
    }
    expectAttestationFailure("unsupported version") {
        _ = try version(Data("Sequence/1".utf8), signature: "")
    }
}

@Test func TestSignInRejectsVersion1AttestationBeforeTheCodeIsRequested() async throws {
    let signer = MockCredentialSigner()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Version1AttestationURLProtocol.self]
    let transport = AttestedSignedWaasTransport(
        publishableKey: "test-publishable-key",
        scope: "test-project-id",
        signer: signer,
        trustedPcr0s: Set([Version1AttestationURLProtocol.pcr0.map { String(format: "%02x", $0) }.joined()]),
        session: URLSession(configuration: configuration)
    )
    let fixture = makeMockWalletClient(
        signer: signer,
        authClient: WaasClient(baseURL: "https://wallet-auth.test", transport: transport)
    )

    do {
        try await fixture.client.startEmailAuth(email: "user@example.com")
        Issue.record("Expected sign-in to reject a version 1 attestation")
    } catch let error as OMSWalletError {
        #expect(error.code == .attestationVerificationFailed)
        #expect(error.operation == .walletStartEmailAuth)
        #expect(error.errorDescription?.contains("version 1 is older than this request requires") == true)
    }
    #expect(fixture.client.pendingEmailAuth == nil)
    #expect(fixture.client.verifier.isEmpty)
    #expect(fixture.transport.requestCount(for: WaasAPI.CompleteAuth.urlPath) == 0)
}

private final class Version1AttestationURLProtocol: URLProtocol, @unchecked Sendable {
    static let pcr0 = Data(repeating: 0xaa, count: 48)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = #"{"verifier":"verifier","loginHint":"user@example.com","challenge":"challenge"}"#
        let document = try! syntheticAttestationDocument(
            timestamp: Date(),
            pcr0: Self.pcr0,
            nonce: request.value(forHTTPHeaderField: "X-Attestation-Nonce") ?? "",
            userData: attestationUserData("Sequence/1", "POST \(request.url!.path)\n\n\(body)")
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-Attestation-Document": document]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func expectAttestationFailure(
    _ expectedMessage: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected attestation verification to fail")
    } catch let error as OMSWalletError {
        #expect(error.code == .attestationVerificationFailed)
        #expect(error.errorDescription?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func TestWalletImportPrivateKeyStringFormsRedactTheKey() {
    let hexKey = "0x" + String(repeating: "ab", count: 32)
    let solanaKey = "5MaiiCavjCmn9Hs1o3eznqDEhRwxo7pXiAYez7keQUviUkauRiTMD8DrESdrNjN8zd9mTmVhRvBJeg5vhyvgrAhG"
    let bytes = Data(repeating: 0xab, count: 32)
    let cases: [(WalletImportPrivateKey, String, String)] = [
        (.ethereum(hexKey), "ethereum", hexKey),
        (.ethereumBytes(bytes), "ethereumBytes", String(repeating: "ab", count: 32)),
        (.solana(solanaKey), "solana", solanaKey),
        (.solanaBytes(bytes), "solanaBytes", String(repeating: "ab", count: 32)),
        (.tron(hexKey), "tron", hexKey),
        (.tronBytes(bytes), "tronBytes", String(repeating: "ab", count: 32)),
    ]
    for (privateKey, caseName, keyMaterial) in cases {
        let expected = "WalletImportPrivateKey.\(caseName)(<redacted>)"
        for rendered in [String(describing: privateKey), String(reflecting: privateKey), "\(privateKey)"] {
            #expect(rendered == expected)
            #expect(!rendered.contains(keyMaterial))
            #expect(!rendered.contains(String(keyMaterial.dropFirst(2))))
        }
        var dumped = ""
        dump(privateKey, to: &dumped)
        #expect(dumped.contains(expected))
        #expect(!dumped.contains(keyMaterial))
        #expect(!dumped.contains(String(keyMaterial.dropFirst(2))))
        #expect(!dumped.contains("32 bytes"))
        #expect(Mirror(reflecting: privateKey).children.isEmpty)
    }
}
