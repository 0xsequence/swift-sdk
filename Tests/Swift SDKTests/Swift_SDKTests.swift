import Testing
@testable import Swift_SDK

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

@Test func TestCompareWalletAddress() async throws {
    let expected = "0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a"
    
    let walletAddress = try! EthereumSigner.GetWalletAddress(privateKey: privateKey)
    
    #expect(walletAddress == expected)
}
