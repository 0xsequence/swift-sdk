import Foundation
import CryptoKit
import Testing
@testable import OMS_SDK

let privateKey: [UInt8] = [
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
    0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11
]

@Test func TestKeccak256() async throws {
    let input    = "challenge123456"
    let expected = "0x752c0acc530a06ddbccae9295f7fd287037f7e2c19272c7506adce3175075fdd"

    let result = Keccak256.Keccak256(data: input)

    #expect(result == expected)
}

@Test func TestEmailAuthChallenge() async throws {
    let challenge  = "challenge"
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

@Test func TestAuthorizationHeaderUsesCredentialKeyType() async throws {
    let credential = "0x04" + String(repeating: "11", count: 64)
    let signature = "0x" + String(repeating: "22", count: 64)
    let header = RequestUtils.buildAuthorizationHeader(
        keyType: .webCryptoSecp256r1,
        scope: "proj_1",
        cred: credential,
        nonce: "1234567890",
        sig: signature
    )
    let expected = "webcrypto-secp256r1 scope=\"proj_1\",cred=\"\(credential)\",nonce=1234567890,sig=\"\(signature)\""

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

@Test func TestGetTokenBalances() async throws {
    let oms = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )
    
    let result = try await oms.indexer.getTokenBalances(
        network: Network.polygon,
        contractAddress: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
        walletAddress: "0x8e3E38fe7367dd3b52D1e281E4e8400447C8d8B9",
        includeMetadata: true
    )
    
    for r in result.balances {
        print("Account Address: \(r.accountAddress ?? "undefined"), Balance: \(r.balance ?? "undefined")")
    }
}

@Test func TestParseUnits() throws {
    #expect(try parseUnits(value: "1", decimals: 18) == "1000000000000000000")
    #expect(try parseUnits(value: "1.23", decimals: 6) == "1230000")
    #expect(try parseUnits(value: ".5", decimals: 6) == "500000")
    #expect(try parseUnits(value: "1.2300", decimals: 2) == "123")
    #expect(try parseUnits(value: "0.000000000000000001", decimals: 18) == "1")
}

@Test func TestSupportedNetworks() throws {
    #expect(Network.supportedNetworks == [.polygon, .polygonAmoy])

    #expect(Network.from(chainId: "137") == .polygon)
    #expect(Network.from(chainId: "80002") == .polygonAmoy)
    #expect(Network.from(chainId: "1") == nil)

    #expect(Network.polygon.displayName == "Polygon")
    #expect(Network.polygon.description == "Polygon")
}

@Test func TestIndexerURLUsesNetworkIndexerName() throws {
    let environment = OMSClientEnvironment(
        indexerURLTemplate: "https://{value}-indexer.sequence.app/rpc/Indexer/"
    )

    #expect(environment.indexerURLTemplate == "https://{value}-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygon)?.absoluteString == "https://polygon-indexer.sequence.app/rpc/Indexer/")
    #expect(environment.indexerURL(for: .polygonAmoy)?.absoluteString == "https://amoy-indexer.sequence.app/rpc/Indexer/")
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
