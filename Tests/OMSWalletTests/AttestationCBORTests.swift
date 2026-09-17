import Foundation
import Testing
@testable import OMSWallet

@Test func TestAttestationCBOREncodesCoseSignatureStructureDeterministically() throws {
    let encoded = try AttestationCBOR.encode(.array([
        .textString("Signature1"),
        .byteString(Data([1, 2, 3])),
        .byteString(Data()),
        .byteString(Data([4, 5]))
    ]))

    let hex = encoded.map { String(format: "%02x", $0) }.joined()
    #expect(hex == "846a5369676e6174757265314301020340420405")
}

@Test func TestAttestationCBORDecodesRequiredNitroValueShapes() throws {
    let encoded = try AttestationCBOR.encode(.tagged(18, .map([
        (.textString("digest"), .textString("SHA384")),
        (.textString("timestamp"), .unsigned(1_800_000_000_000)),
        (.textString("pcrs"), .map([(.unsigned(0), .byteString(Data(repeating: 0xaa, count: 48)))])),
        (.textString("optional"), .null)
    ])))
    let decoded = try AttestationCBOR.decode(encoded)

    guard case .tagged(18, let payload) = decoded else {
        Issue.record("Expected tagged attestation payload")
        return
    }
    guard case .textString("SHA384")? = payload.value(forTextKey: "digest"),
          case .unsigned(1_800_000_000_000)? = payload.value(forTextKey: "timestamp"),
          case .map(let pcrs)? = payload.value(forTextKey: "pcrs"),
          case .byteString(let pcr0)? = pcrs.first?.1 else {
        Issue.record("Expected decoded attestation fields")
        return
    }
    #expect(pcr0 == Data(repeating: 0xaa, count: 48))
}

@Test func TestAttestationVerifierAcceptsRealNitroDocument() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "attestation", withExtension: "json", subdirectory: "Fixtures")
    )
    let fixture = try JSONDecoder().decode(
        RealAttestationFixture.self,
        from: Data(contentsOf: fixtureURL)
    )
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let now = try #require(dateFormatter.date(from: fixture.now))

    try AttestationVerifier.verify(
        encodedDocument: fixture.encodedDocument.trimmingCharacters(in: .whitespacesAndNewlines),
        method: fixture.method,
        path: fixture.path,
        requestBody: fixture.requestBody,
        responseBody: fixture.responseBody,
        nonce: fixture.nonce,
        trustedPcr0s: Set([fixture.pcr0]),
        now: now
    )
}

@Test func TestAttestationCBORRejectsMalformedOrUnboundedInput() {
    let invalidInputs = [
        Data([0x00, 0x00]),
        Data([0x9f, 0xff]),
        Data([0xbf, 0x61, 0x61, 0x01]),
        Data([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]),
        Data(repeating: 0x81, count: 17) + Data([0x00]),
        Data([0x5a, 0xff, 0xff, 0xff, 0xff]),
        Data([0x61, 0xff]),
        Data([0xf9, 0x00, 0x00])
    ]

    for input in invalidInputs {
        #expect(throws: AttestationCBOR.CodingError.self) {
            _ = try AttestationCBOR.decode(input)
        }
    }
}

private struct RealAttestationFixture: Decodable {
    let encodedDocument: String
    let method: String
    let path: String
    let requestBody: String
    let responseBody: String
    let nonce: String
    let pcr0: String
    let now: String
}
