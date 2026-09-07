import CryptoKit
import Foundation
import Security
import SwiftCBOR

enum WalletImportAttestationError {
    static let transportPrefix = "WaaS attestation verification failed: "
}

public struct WalletImportConfiguration: Sendable {
    let trustedPcr0s: Set<String>

    public init(trustedPcr0s: [String]) throws {
        let normalized = trustedPcr0s.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "^0x", with: "", options: .regularExpression)
        }
        guard !normalized.isEmpty,
              normalized.allSatisfy({
                  $0.count == 96 && $0.allSatisfy(\.isHexDigit) && $0.contains(where: { $0 != "0" })
              }) else {
            throw OMSWalletError(
                code: .validationError,
                message: "walletImport.trustedPcr0s must contain at least one nonzero 48-byte hex PCR0"
            )
        }
        self.trustedPcr0s = Set(normalized)
    }
}

@available(macOS 12.0, iOS 15.0, *)
struct AttestedSignedWaasTransport: WebRPCTransport {
    let session: URLSession
    private let client: HttpClient
    private let publishableKey: String
    private let scope: String
    private let signer: any CredentialSigner
    private let trustedPcr0s: Set<String>

    init(
        publishableKey: String,
        scope: String,
        signer: any CredentialSigner,
        trustedPcr0s: Set<String>,
        session: URLSession = .shared
    ) {
        self.publishableKey = publishableKey
        self.scope = scope
        self.signer = signer
        self.trustedPcr0s = trustedPcr0s
        self.session = session
        self.client = HttpClient(session: session)
    }

    func post(baseURL: String, path: String, body: Data, headers: [String: String]) async throws -> WebRPCHTTPResponse {
        do {
            let endpoint = resolveEndpoint(path)
            let payload = String(data: body, encoding: .utf8) ?? ""
            let nonce = try randomNonce()
            let authHeader = try buildAuthHeader(endpoint: endpoint, payload: payload)
            var requestHeaders = [
                "Api-Key": publishableKey,
                "OMS-Wallet-Signature": authHeader,
                "X-Attestation-Nonce": nonce
            ]
            headers.forEach { requestHeaders[$0.key] = $0.value }
            let response = try await client.postJson(
                baseUrl: baseURL,
                path: path,
                body: payload,
                headers: requestHeaders
            )
            guard let encodedDocument = response.headers["x-attestation-document"] else {
                throw attestationError("WaaS response is missing its attestation document")
            }
            try AttestationVerifier.verify(
                encodedDocument: encodedDocument,
                method: "POST",
                path: path.hasPrefix("/") ? path : "/\(path)",
                requestBody: payload,
                responseBody: String(data: response.body, encoding: .utf8) ?? "",
                nonce: nonce,
                trustedPcr0s: trustedPcr0s
            )
            return WebRPCHTTPResponse(statusCode: response.statusCode, body: response.body)
        } catch let error as OMSWalletError where error.code == .attestationVerificationFailed {
            throw WebRPCTransportError(
                message: WalletImportAttestationError.transportPrefix
                    + (error.errorDescription ?? "WaaS attestation verification failed"),
                underlyingDescription: error.errorDescription
            )
        }
    }

    private func buildAuthHeader(endpoint: String, payload: String) throws -> String {
        let nonce = try signer.nextNonce()
        let preimage = RequestUtils.buildWalletRequestPreimage(
            endpoint: endpoint,
            nonce: nonce,
            scope: scope,
            payload: payload
        )
        return try RequestUtils.buildWalletSignatureHeader(
            alg: signer.alg,
            scope: scope,
            cred: signer.credentialId(),
            nonce: nonce,
            sig: signer.sign(preimage: preimage)
        )
    }

    private func resolveEndpoint(_ path: String) -> String {
        if path.hasPrefix(WaasAPI.basePath) { return String(path.dropFirst(WaasAPI.basePath.count)) }
        return path.hasPrefix("/") ? path : "/\(path)"
    }

    private func randomNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw attestationError("Unable to generate an attestation nonce")
        }
        return Data(bytes).base64EncodedString()
    }
}

enum AttestationVerifier {
    private static let rootSha256 = "641a0321a3e244efe456463195d606317ed7cdcc3c1756e09893f3c68f79bb5b"
    private static let maxAge: TimeInterval = 5 * 60

    static func verify(
        encodedDocument: String,
        method: String,
        path: String,
        requestBody: String,
        responseBody: String,
        nonce: String,
        trustedPcr0s: Set<String>,
        now: Date = Date()
    ) throws {
        guard let documentBytes = Data(base64Encoded: encodedDocument),
              documentBytes.base64EncodedString() == encodedDocument,
              let decoded = try CBOR.decode([UInt8](documentBytes)),
              case .tagged(let tag, .array(let cose)) = decoded,
              tag.rawValue == 18,
              cose.count == 4,
              case .byteString(let protectedHeader) = cose[0],
              case .map(let unprotectedHeader) = cose[1], unprotectedHeader.isEmpty,
              case .byteString(let payload) = cose[2],
              case .byteString(let signature) = cose[3], signature.count == 96 else {
            throw attestationError("WaaS attestation has an invalid COSE_Sign1 structure")
        }
        guard let protected = try CBOR.decode(protectedHeader),
              case .map(let protectedMap) = protected,
              protectedMap[.unsignedInt(1)] == .negativeInt(34) else {
            throw attestationError("WaaS attestation does not use COSE ES384")
        }
        guard let payloadValue = try CBOR.decode(payload), case .map(let fields) = payloadValue else {
            throw attestationError("WaaS attestation payload is not a CBOR map")
        }
        guard fields["digest"] == .utf8String("SHA384"),
              case .unsignedInt(let timestamp) = fields["timestamp"],
              case .map(let pcrs) = fields["pcrs"],
              case .byteString(let certificate) = fields["certificate"],
              case .array(let bundleValues) = fields["cabundle"],
              case .byteString(let userData) = fields["user_data"],
              case .byteString(let documentNonce) = fields["nonce"] else {
            throw attestationError("WaaS attestation payload is missing required fields")
        }
        let timestampDate = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1_000)
        guard abs(timestampDate.timeIntervalSince(now)) <= maxAge else {
            throw attestationError("WaaS attestation timestamp is outside the accepted freshness window")
        }
        guard !pcrs.isEmpty, pcrs.count <= 32 else {
            throw attestationError("WaaS attestation contains an invalid PCR measurement")
        }
        for (index, measurement) in pcrs {
            guard case .unsignedInt(let index) = index, index < 32,
                  case .byteString(let bytes) = measurement,
                  [32, 48, 64].contains(bytes.count) else {
                throw attestationError("WaaS attestation contains an invalid PCR measurement")
            }
        }
        guard case .byteString(let pcr0)? = pcrs[.unsignedInt(0)],
              trustedPcr0s.contains(Data(pcr0).hexString) else {
            throw attestationError("WaaS attestation PCR0 is not trusted")
        }
        guard Data(documentNonce) == Data(nonce.utf8) else {
            throw attestationError("WaaS attestation nonce does not match the request")
        }
        let preimage = "\(method.uppercased()) \(path)\n\(requestBody)\n\(responseBody)"
        let hash = Data(SHA256.hash(data: Data(preimage.utf8))).base64EncodedString()
        guard Data(userData) == Data("Sequence/1:\(hash)".utf8) else {
            throw attestationError("WaaS attestation is not bound to the request and response")
        }
        let bundle = try bundleValues.map { value -> Data in
            guard case .byteString(let bytes) = value else {
                throw attestationError("WaaS attestation certificate bundle is invalid")
            }
            return Data(bytes)
        }
        let leafKey = try verifyCertificateChain(leaf: Data(certificate), bundle: bundle, now: now)
        let signatureInput = Data(CBOR.encode(CBOR.array([
            .utf8String("Signature1"),
            .byteString(protectedHeader),
            .byteString([]),
            .byteString(payload)
        ])))
        let derSignature = try rawEcdsaSignatureToDer(Data(signature), componentSize: 48)
        guard SecKeyVerifySignature(
            leafKey,
            .ecdsaSignatureMessageX962SHA384,
            signatureInput as CFData,
            derSignature as CFData,
            nil
        ) else {
            throw attestationError("WaaS attestation signature is invalid")
        }
    }

    private static func verifyCertificateChain(leaf: Data, bundle: [Data], now: Date) throws -> SecKey {
        // AWS specifies cabundle as [ROOT_CERT, INTERM_1, ..., INTERM_N].
        // https://docs.aws.amazon.com/enclaves/latest/user/verify-root.html
        guard let rootData = bundle.first,
              Data(SHA256.hash(data: rootData)).hexString == rootSha256,
              let leafCertificate = SecCertificateCreateWithData(nil, leaf as CFData) else {
            throw attestationError("WaaS attestation certificate chain does not use the AWS Nitro root")
        }
        let authorities = try bundle.map { data -> SecCertificate in
            guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
                throw attestationError("WaaS attestation certificate bundle is invalid")
            }
            return certificate
        }
        var trust: SecTrust?
        let certificates: [SecCertificate] = [leafCertificate] + authorities.dropFirst()
        guard SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else {
            throw attestationError("WaaS attestation certificate chain is invalid")
        }
        SecTrustSetAnchorCertificates(trust, [authorities[0]] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetVerifyDate(trust, now as CFDate)
        guard SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              chain.count == bundle.count + 1,
              let trustedRoot = chain.last,
              SecCertificateCopyData(trustedRoot) as Data == rootData,
              let key = SecCertificateCopyKey(leafCertificate) else {
            throw attestationError("WaaS attestation certificate chain is incomplete")
        }
        return key
    }

    private static func rawEcdsaSignatureToDer(_ raw: Data, componentSize: Int) throws -> Data {
        guard raw.count == componentSize * 2 else { throw attestationError("WaaS attestation signature is invalid") }
        func integer(_ value: Data) -> Data {
            var bytes = Array(value.drop(while: { $0 == 0 }))
            if bytes.isEmpty { bytes = [0] }
            if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
            return Data([0x02]) + derLength(bytes.count) + Data(bytes)
        }
        let r = integer(raw.prefix(componentSize))
        let s = integer(raw.suffix(componentSize))
        return Data([0x30]) + derLength(r.count + s.count) + r + s
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 128 { return Data([UInt8(length)]) }
        return Data([0x81, UInt8(length)])
    }
}

func attestationError(_ message: String) -> OMSWalletError {
    OMSWalletError(code: .attestationVerificationFailed, message: message)
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
