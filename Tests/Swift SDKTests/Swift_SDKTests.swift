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

@Test func TestEthereumSign() async throws {
    let message  = "hello"
    let expected = "0xc2af8d3c8c18ecceb558734b6d43e8126ca59f38ed1c3fd13da87f1fe2d96dd1753686b2f601bccd13af820a4078437825c8cad005e3cf607b95a38ec5247c571c"

    let hashedResult = Keccak256.Keccak256(data: message)
    let result = try! EthereumSigner.signUTF8MessageEIP191(privateKey: privateKey, message: hashedResult)
    
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


@Test func TestCompareWalletAddress() async throws {
    let expected = "0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a"
    
    let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: privateKey)
    
    #expect(walletAddress == expected)
}

@Test func TestGetTokenBalances() async throws {
    let oms = OMSClient(
        projectAccessKey: "AQAAAAAAAAK2JvvZhWqZ51riasWBftkrVXE"
    )
    
    let result = try await oms.indexer.getTokenBalances(
        chainId: "polygon",
        contractAddress: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
        walletAddress: "0x8e3E38fe7367dd3b52D1e281E4e8400447C8d8B9",
        includeMetadata: true
    )
    
    for r in result.balances {
        print("Account Address: \(r.accountAddress ?? "undefined"), Balance: \(r.balance ?? "undefined")")
    }
}

@Test func TestParseUnits() throws {
    let utils = OMSClient(projectAccessKey: "test").utils

    #expect(try utils.parseUnits(value: "1", decimals: 18) == "1000000000000000000")
    #expect(try utils.parseUnits(value: "1.23", decimals: 6) == "1230000")
    #expect(try utils.parseUnits(value: ".5", decimals: 6) == "500000")
    #expect(try utils.parseUnits(value: "1.2300", decimals: 2) == "123")
    #expect(try utils.parseEther(value: "0.000000000000000001") == "1")
}

@Test func TestFormatUnits() throws {
    let utils = OMSClient(projectAccessKey: "test").utils

    #expect(try utils.formatUnits(value: "1000000000000000000", decimals: 18) == "1")
    #expect(try utils.formatUnits(value: "1230000", decimals: 6) == "1.23")
    #expect(try utils.formatUnits(value: "1", decimals: 6) == "0.000001")
    #expect(try utils.formatUnits(value: "1230000", decimals: 6, trimTrailingZeros: false) == "1.230000")
    #expect(try utils.formatEther(value: "1") == "0.000000000000000001")
}

@Test func TestParseUnitsRejectsTooManyDecimals() {
    let utils = OMSClient(projectAccessKey: "test").utils

    do {
        _ = try utils.parseUnits(value: "1.234", decimals: 2)
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
