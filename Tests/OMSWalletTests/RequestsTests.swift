import Foundation
import CryptoKit
import Testing
@testable import OMSWallet

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

@Test func TestOidcIdTokenPayloadHelpersMatchParityVector() throws {
    let idToken = try fakeOidcIdToken(exp: 1_910_000_100)

    #expect(try OidcIdToken.expiresAtEpochSeconds(idToken) == 1_910_000_100)
    #expect(OidcIdToken.handleHash(idToken) == expectedOidcHandleHash(idToken))
}

@Test func TestOidcIdTokenRequiresExpirationClaim() throws {
    let idToken = try fakeOidcIdToken(payload: ["sub": "oidc-sub-123"])

    do {
        _ = try OidcIdToken.expiresAtEpochSeconds(idToken)
        #expect(Bool(false))
    } catch let error as OidcIdTokenError {
        #expect(error == .missingExpiration)
    } catch {
        #expect(Bool(false))
    }
}

@Test func TestOidcIdTokenRejectsOutOfRangeNumericExpirationClaim() throws {
    let idToken = try fakeOidcIdToken(payload: ["exp": 1e100])

    do {
        _ = try OidcIdToken.expiresAtEpochSeconds(idToken)
        #expect(Bool(false))
    } catch let error as OidcIdTokenError {
        #expect(error == .invalidExpiration)
    } catch {
        #expect(Bool(false))
    }
}

@Test func TestP256RawSignatureDerRoundTrip() throws {
    let expectedRawSignature = Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x80)]
        + Array(repeating: UInt8(0), count: 31)
        + [UInt8(0x01)]
    let derSignature = Data(
        [0x30, 0x07, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]
    )

    let decoded = try P256EcdsaSignatureEncoding.derToRaw(derSignature)

    #expect(decoded == expectedRawSignature)
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

@Test func TestParseUnitsRoundsExtraPrecisionToNearestBaseUnit() throws {
    #expect(try parseUnits(value: "1.2345", decimals: 2) == "123")
    #expect(try parseUnits(value: "1.235", decimals: 2) == "124")
    #expect(try parseUnits(value: "1.995", decimals: 2) == "200")
    #expect(try parseUnits(value: "1.5", decimals: 0) == "2")
    #expect(try parseUnits(value: "-1.5", decimals: 0) == "-2")
    #expect(try parseUnits(value: "0.0000000000000000005", decimals: 18) == "1")
}

@Test func TestOMSWalletSessionStateParsesExpiresAt() throws {
    let state = OMSWalletSessionState(
        walletAddress: "0xabc",
        expiresAtString: "2026-01-01T00:00:00Z",
        auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    )

    #expect(state.walletAddress == "0xabc")
    #expect(state.expiresAt == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(state.auth == .email(OMSWalletEmailSessionAuth(email: "user@example.com")))
    #expect(state.auth?.email == "user@example.com")
}

@Test func TestStorableCredentialsRoundTripSessionMetadata() throws {
    let credentials = StorableCredentials(
        walletId: "wallet-1",
        walletAddress: "0xabc",
        signerCredentialId: "0xsigner",
        alg: .ecdsaP256Sha256,
        expiresAt: "2026-01-01T00:00:00Z",
        auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    )

    let restored = try StorableCredentials.from(jsonString: credentials.jsonString())

    #expect(restored.walletId == "wallet-1")
    #expect(restored.walletAddress == "0xabc")
    #expect(restored.signerCredentialId == "0xsigner")
    #expect(restored.alg == .ecdsaP256Sha256)
    #expect(restored.expiresAt == "2026-01-01T00:00:00Z")
    #expect(restored.auth == .email(OMSWalletEmailSessionAuth(email: "user@example.com")))
}

@Test func TestPendingOidcRedirectAuthRoundTripStoresRedirectAuthMode() throws {
    let pending = PendingOidcRedirectAuth(
        verifier: "verifier",
        challenge: "challenge",
        nonce: "nonce-123",
        authMode: .authCode,
        redirectUri: "omsclientswiftdemo://auth/callback",
        issuer: "https://issuer.example",
        provider: "custom",
        providerLabel: "Custom",
        authorizationScope: "proj_1",
        walletType: .ethereum,
        walletSelection: .manual,
        sessionLifetimeSeconds: 120,
        signerCredentialId: "0xcredential",
        signerKeyType: .ecdsaP256Sha256
    )

    let json = try pending.jsonString()
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let restored = try PendingOidcRedirectAuth.from(jsonString: json)

    #expect(object["authMode"] as? String == "auth-code")
    #expect(object["provider"] as? String == "custom")
    #expect(object["providerLabel"] as? String == "Custom")
    #expect(object["walletSelection"] as? String == "manual")
    #expect(object["sessionLifetimeSeconds"] as? Int == 120)
    #expect(restored.authMode == .authCode)
    #expect(restored.provider == "custom")
    #expect(restored.providerLabel == "Custom")
    #expect(restored.walletSelection == .manual)
    #expect(restored.sessionLifetimeSeconds == 120)
}

@Test func TestOidcRedirectAuthMatchesCustomSchemesWithoutAuthority() throws {
    #expect(
        OidcRedirectAuth.matchesRedirectUri(
            callbackUrl: "omsclientswiftdemo:/callback?code=auth-code&state=state-123",
            redirectUri: "omsclientswiftdemo:/callback"
        )
    )
}

@Test func TestOidcRedirectAuthRejectsInvalidStateWithoutClearingPendingAuth() throws {
    let pending = PendingOidcRedirectAuth(
        verifier: "verifier",
        challenge: "challenge",
        nonce: "nonce-123",
        authMode: .authCodePkce,
        redirectUri: "omsclientswiftdemo://auth/callback",
        issuer: "https://issuer.example",
        provider: nil,
        providerLabel: nil,
        authorizationScope: "proj_1",
        walletType: .ethereum,
        walletSelection: nil,
        sessionLifetimeSeconds: nil,
        signerCredentialId: "0xcredential",
        signerKeyType: .ecdsaP256Sha256
    )

    do {
        try OidcRedirectAuth.validateState("not-base64", pending: pending)
        #expect(Bool(false))
    } catch let error as OidcRedirectAuthError {
        #expect(error == .invalidState)
    } catch {
        #expect(Bool(false))
    }
}

func fakeOidcIdToken(exp: Int64 = 1_910_000_100) throws -> String {
    try fakeOidcIdToken(payload: [
        "iss": "https://accounts.google.com",
        "aud": "demo-web-client-id",
        "sub": "google-sub-123",
        "email": "user@example.com",
        "exp": exp
    ])
}

func fakeOidcIdToken(payload: [String: Any]) throws -> String {
    let header = try base64UrlEncodeJSONObject([
        "alg": "none",
        "typ": "JWT"
    ])
    let body = try base64UrlEncodeJSONObject(payload)
    return [header, body, "test-signature"].joined(separator: ".")
}

func expectedOidcHandleHash(_ idToken: String) -> String {
    let digest = SHA256.hash(data: Data(idToken.utf8))
    return base64UrlEncode(Data(digest))
}

private func base64UrlEncodeJSONObject(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return base64UrlEncode(data)
}

private func base64UrlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
