import Foundation
import Testing
@testable import OMS_SDK

@Test func TestKeccak256() async throws {
    let input = "challenge123456"
    let expected = "0x752c0acc530a06ddbccae9295f7fd287037f7e2c19272c7506adce3175075fdd"

    let result = Keccak256.Keccak256(data: input)

    #expect(result == expected)
}

@Test func TestEmailAuthChallenge() async throws {
    let challenge = "challenge"
    let code = "123456"
    let expected = "2oXiHHjzvN3XzdxGxWTK_c9hZf7pom0OovssPvI7q3M"

    let answer = RequestUtils.hashEmailAuthAnswer(
        challenge: challenge,
        code: code
    )

    #expect(answer == expected)
}

@Test func TestWalletRequestPreimageIncludesScope() async throws {
    let payload = "{\"verifier\":\"email@example.com\"}"
    let expected = """
    POST /rpc/Wallet/CommitVerifier
    nonce: 1234567890
    scope: proj_1

    {"verifier":"email@example.com"}
    """

    let preimage = RequestUtils.buildWalletRequestPreimage(
        endpoint: "/CommitVerifier",
        nonce: "1234567890",
        scope: OMSClientEnvironment.defaultScope,
        payload: payload
    )

    #expect(preimage == expected)
}

@Test func TestWalletSignatureHeaderUsesSigningAlgorithm() async throws {
    let credential = "0x04" + String(repeating: "11", count: 64)
    let signature = "0x" + String(repeating: "22", count: 64)
    let header = RequestUtils.buildWalletSignatureHeader(
        alg: .ecdsaP256Sha256,
        scope: "proj_1",
        cred: credential,
        nonce: "1234567890",
        sig: signature
    )
    let expected = "alg=\"ecdsa-p256-sha256\", scope=\"proj_1\", cred=\"\(credential)\", nonce=1234567890, sig=\"\(signature)\""

    #expect(header == expected)
}

@Test func TestP256RawSignatureDerRoundTrip() throws {
    let rawSignature = Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x80)]
        + Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x01)]

    let derSignature = try P256EcdsaSignatureEncoding.rawToDer(rawSignature)
    let decoded = try P256EcdsaSignatureEncoding.derToRaw(derSignature)

    #expect(decoded == rawSignature)
}

@Test func TestParseUnits() throws {
    #expect(try parseUnits(value: "1", decimals: 18) == "1000000000000000000")
    #expect(try parseUnits(value: "1.23", decimals: 6) == "1230000")
    #expect(try parseUnits(value: ".5", decimals: 6) == "500000")
    #expect(try parseUnits(value: "1.2300", decimals: 2) == "123")
    #expect(try parseUnits(value: "0.000000000000000001", decimals: 18) == "1")
}

@Test func TestFormatUnits() throws {
    #expect(try formatUnits(value: "1000000000000000000", decimals: 18) == "1")
    #expect(try formatUnits(value: "1230000", decimals: 6) == "1.23")
    #expect(try formatUnits(value: "1", decimals: 6) == "0.000001")
    #expect(try formatUnits(value: "1200000", decimals: 6) == "1.2")
    #expect(try formatUnits(value: "1", decimals: 18) == "0.000000000000000001")
}

@Test func TestParseUnitsRejectsTooManyDecimals() {
    do {
        _ = try parseUnits(value: "1.234", decimals: 2)
        #expect(Bool(false))
    } catch UnitConversionError.fractionalComponentExceedsDecimals(let value, let decimals) {
        #expect(value == "1.234")
        #expect(decimals == 2)
    } catch {
        #expect(Bool(false))
    }
}

@Test func TestCheapestFeeOptionUsesNumericValue() async throws {
    let token = FeeToken(
        network: "polygon",
        name: "USDC",
        symbol: "USDC",
        type: "erc20",
        logoUrl: "",
        tokenId: "usdc"
    )
    let options = [
        FeeOption(token: token, value: "100", displayValue: "100"),
        FeeOption(token: token, value: "20", displayValue: "20")
    ]

    let selected = try await FeeOptionSelector.cheapest(options)

    #expect(selected.value == "20")
}

@Test func TestSessionStateParsesExpiresAt() throws {
    let state = SessionState(
        walletAddress: "0xabc",
        expiresAtString: "2026-01-01T00:00:00Z",
        loginType: .email,
        sessionEmail: "user@example.com"
    )

    #expect(state.walletAddress == "0xabc")
    #expect(state.expiresAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(state.loginType == .email)
    #expect(state.sessionEmail == "user@example.com")
}

@Test func TestStorableCredentialsRoundTripSessionMetadata() throws {
    let credentials = StorableCredentials(
        walletId: "wallet-1",
        walletAddress: "0xabc",
        signerCredentialId: "0xsigner",
        alg: .ecdsaP256Sha256,
        expiresAt: "2026-01-01T00:00:00Z",
        loginType: .email,
        sessionEmail: "user@example.com"
    )

    let restored = try StorableCredentials.from(jsonString: credentials.jsonString())

    #expect(restored.walletId == "wallet-1")
    #expect(restored.walletAddress == "0xabc")
    #expect(restored.signerCredentialId == "0xsigner")
    #expect(restored.alg == .ecdsaP256Sha256)
    #expect(restored.expiresAt == "2026-01-01T00:00:00Z")
    #expect(restored.loginType == .email)
    #expect(restored.sessionEmail == "user@example.com")
}

@Test func TestOMSClientIdentityMapsSessionLoginType() throws {
    let emailIdentity = OMSClientIdentity(Identity(type: .email, sub: "user@example.com"))
    let googleIdentity = OMSClientIdentity(Identity(type: .oidc, iss: "https://accounts.google.com", sub: "google-sub"))
    let oidcIdentity = OMSClientIdentity(Identity(type: .oidc, iss: "https://idp.example.com", sub: "oidc-sub"))
    let phoneIdentity = OMSClientIdentity(Identity(type: .phone, sub: "+15555550100"))

    #expect(emailIdentity.sessionLoginType == .email)
    #expect(googleIdentity.sessionLoginType == .googleAuth)
    #expect(oidcIdentity.sessionLoginType == .oidc)
    #expect(phoneIdentity.sessionLoginType == nil)
}
