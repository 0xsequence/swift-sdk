import CryptoKit
import Foundation
import Testing
@testable import OMSWallet

private let tronWalletAddress = "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL"
private let tronWalletHex = "0x8840e6c55b9ada326d211d818c34a994aeced808"
private let tronRecipient = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
private let tronUsdt = "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private func makeActiveWalletFixture(
    type: WalletType = .tron,
    address: String = tronWalletAddress
) -> MockWalletClientFixture {
    let fixture = makeMockWalletClient()
    fixture.client.walletId = "wallet-id"
    fixture.client.activeWallet = Wallet(id: "wallet-id", type: type, address: address, keyOrigin: .enclave)
    fixture.client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    fixture.client.sessionAuth = .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    return fixture
}

private func sponsoredPrepareResponse(_ txnId: String) -> PrepareResponse {
    PrepareResponse(
        txnId: txnId,
        status: .quoted,
        feeOptions: [],
        sponsored: true,
        expiresAt: "2099-01-01T00:00:00Z"
    )
}

private func expectValidationError<T>(
    _ operation: OMSWalletOperation,
    _ body: () async throws -> T
) async {
    do {
        _ = try await body()
        Issue.record("Expected a validation error for \(operation.rawValue)")
    } catch let error as OMSWalletError {
        #expect(error.code == .validationError)
        #expect(error.operation == operation)
    } catch {
        Issue.record("Expected OMSWalletError, got \(error)")
    }
}

@Test func TestTronSendTransactionOmitsDataForPlainTrxTransferInNativeMode() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.transport.enqueue(sponsoredPrepareResponse("txn-trx"), for: WaasAPI.PrepareTronTransaction.urlPath)
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)
    try fixture.transport.enqueue(
        WaasTransactionStatusResponse(status: .executed, txnHash: "tron-txid"),
        for: WaasAPI.TransactionStatusMethod.urlPath
    )

    let result = try await fixture.client.sendTronTransaction(
        network: .nile,
        to: tronRecipient,
        value: "1000000"
    )

    let prepare = try fixture.transport.requestObject(for: WaasAPI.PrepareTronTransaction.urlPath)
    let execute = try fixture.transport.requestObject(for: WaasAPI.Execute.urlPath)
    let expectedPrepare: NSDictionary = [
        "network": "tron:nile",
        "walletId": "wallet-id",
        "to": tronRecipient,
        "value": "1000000",
        "mode": "native"
    ]
    #expect(prepare == expectedPrepare)
    #expect(prepare["data"] == nil)
    #expect(execute == (["txnId": "txn-trx"] as NSDictionary))
    #expect(result.txnId == "txn-trx")
    #expect(result.status == .executed)
    #expect(result.txnHash == "tron-txid")
    #expect(result.statusResolution == .resolved)
}

@Test func TestTronSendTransactionForwardsEmptyDataAsPayableFallbackCall() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.transport.enqueue(sponsoredPrepareResponse("txn-fallback"), for: WaasAPI.PrepareTronTransaction.urlPath)
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)

    let result = try await fixture.client.sendTronTransaction(
        network: .nile,
        to: tronUsdt,
        data: "0x",
        waitForStatus: false
    )

    let prepare = try fixture.transport.requestObject(for: WaasAPI.PrepareTronTransaction.urlPath)
    let expectedPrepare: NSDictionary = [
        "network": "tron:nile",
        "walletId": "wallet-id",
        "to": tronUsdt,
        "value": "0",
        "data": "0x",
        "mode": "native"
    ]
    #expect(prepare == expectedPrepare)
    #expect(result.txnId == "txn-fallback")
    #expect(result.status == .pending)
}

@Test func TestTronCallContractPreparesTrc20TransferThroughWalletServiceEncoder() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.transport.enqueue(sponsoredPrepareResponse("txn-trc20"), for: WaasAPI.PrepareTronContractCall.urlPath)
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)

    let result = try await fixture.client.callTronContract(
        network: .mainnet,
        contract: tronUsdt,
        method: "transfer",
        args: [
            AbiArg(type: "address", value: .string(tronRecipient)),
            AbiArg(type: "uint256", value: .string("1000000"))
        ],
        waitForStatus: false
    )

    let prepare = try fixture.transport.requestObject(for: WaasAPI.PrepareTronContractCall.urlPath)
    let expectedPrepare: NSDictionary = [
        "network": "tron:mainnet",
        "walletId": "wallet-id",
        "contract": tronUsdt,
        "method": "transfer",
        "args": [
            ["type": "address", "value": tronRecipient],
            ["type": "uint256", "value": "1000000"]
        ],
        "mode": "native"
    ]
    #expect(prepare == expectedPrepare)
    #expect(result.txnId == "txn-trc20")
}

@Test(arguments: ["transfer(address,uint256)", "transfer ", "", "1transfer", "trans-fer"])
func TestContractCallsRejectNonBareMethodNamesBeforeAnyRequest(method: String) async throws {
    let tron = makeActiveWalletFixture()
    await expectValidationError(.walletCallTronContract) {
        try await tron.client.callTronContract(
            network: .nile,
            contract: tronUsdt,
            method: method,
            args: [AbiArg(type: "uint256", value: .string("1"))]
        )
    }

    let ethereum = makeActiveWalletFixture(type: .ethereum, address: "0x9999999999999999999999999999999999999999")
    await expectValidationError(.walletCallContract) {
        try await ethereum.client.callContract(
            network: .polygon,
            contract: "0x1111111111111111111111111111111111111111",
            method: method,
            args: nil
        )
    }

    #expect(tron.transport.totalRequestCount == 0)
    #expect(ethereum.transport.totalRequestCount == 0)
}

@Test func TestContractCallsAcceptBareMethodNames() async throws {
    let fixture = makeActiveWalletFixture()
    for method in ["transfer", "_mint", "balanceOf2"] {
        try fixture.transport.enqueue(sponsoredPrepareResponse("txn-\(method)"), for: WaasAPI.PrepareTronContractCall.urlPath)
        try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)
        let result = try await fixture.client.callTronContract(
            network: .nile,
            contract: tronUsdt,
            method: method,
            waitForStatus: false
        )
        #expect(result.txnId == "txn-\(method)")
    }
}

@Test func TestTronSponsoredTransactionPassesEmptyFeeOptionsToSelector() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.transport.enqueue(sponsoredPrepareResponse("txn-sponsored"), for: WaasAPI.PrepareTronTransaction.urlPath)
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)
    let receivedOptions = LockedBox<[[FeeOptionWithBalance]]>([])

    _ = try await fixture.client.sendTronTransaction(
        network: .nile,
        to: tronRecipient,
        value: "1",
        selectFeeOption: FeeOptionSelector { options in
            receivedOptions.withValue { $0.append(options) }
            return nil
        },
        waitForStatus: false
    )

    let execute = try fixture.transport.requestObject(for: WaasAPI.Execute.urlPath)
    #expect(receivedOptions.withValue { $0.map(\.count) } == [0])
    #expect(execute == (["txnId": "txn-sponsored"] as NSDictionary))
    #expect(fixture.indexerBackend.tronBalanceRequestPayloads.isEmpty)
}

@Test func TestTronFirstAvailablePaysUnsponsoredFeeWithTrxBalance() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.indexerBackend.setTronBalancesResponse(
        """
        {
          "balances": [
            {
              "network": "tron:nile",
              "accountAddress": "\(tronWalletAddress)",
              "assetType": "native",
              "name": "Tron",
              "symbol": "TRX",
              "decimals": 6,
              "balance": "2000000",
              "formattedBalance": "2",
              "verificationStatus": "unknown",
              "verificationSource": "none"
            }
          ],
          "errors": []
        }
        """
    )
    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-burn",
            status: .quoted,
            feeOptions: [
                WaasFeeOption(
                    token: WaasFeeToken(network: "tron:nile", name: "TRX", symbol: "TRX", type: "NATIVE"),
                    value: "345000",
                    displayValue: "0.345"
                )
            ],
            sponsored: false,
            expiresAt: "2099-01-01T00:00:00Z"
        ),
        for: WaasAPI.PrepareTronTransaction.urlPath
    )
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)
    let receivedOptions = LockedBox<[FeeOptionWithBalance]>([])

    let result = try await fixture.client.sendTronTransaction(
        network: .nile,
        to: tronRecipient,
        value: "1000000",
        selectFeeOption: FeeOptionSelector { options in
            receivedOptions.withValue { $0 = options }
            return try await FeeOptionSelector.firstAvailable(options)
        },
        waitForStatus: false
    )

    let execute = try fixture.transport.requestObject(for: WaasAPI.Execute.urlPath)
    let option = try #require(receivedOptions.withValue { $0.first })
    let expectedIndexerRequest: NSDictionary = [
        "networks": ["tron:nile"],
        "filter": ["accountAddresses": [tronWalletAddress], "omitNativeBalances": false],
        "omitMetadata": true
    ]
    #expect(fixture.indexerBackend.tronBalanceRequestPayloads == [expectedIndexerRequest])
    #expect(option.availableRaw == "2000000")
    #expect(option.available == "2")
    #expect(option.decimals == 6)
    #expect(execute == (["txnId": "txn-burn", "feeOption": ["token": "TRX", "index": 0]] as NSDictionary))
    #expect(result.txnId == "txn-burn")
}

@Test func TestTronFeeBalancesLookUpTrc20ByContractAddress() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.indexerBackend.setTronBalancesResponse(
        """
        {
          "balances": [
            {
              "network": "tron:nile",
              "accountAddress": "\(tronWalletAddress)",
              "assetType": "fungible-token",
              "tokenStandard": "trc20",
              "contractAddress": "\(tronUsdt)",
              "name": "Tether USD",
              "symbol": "USDT",
              "decimals": 6,
              "balance": "5000000",
              "formattedBalance": "5",
              "verificationStatus": "unknown",
              "verificationSource": "none"
            }
          ],
          "errors": []
        }
        """
    )
    try fixture.transport.enqueue(
        PrepareResponse(
            txnId: "txn-usdt-fee",
            status: .quoted,
            feeOptions: [
                WaasFeeOption(
                    token: WaasFeeToken(
                        network: "tron:nile",
                        name: "Tether USD",
                        symbol: "USDT",
                        type: "TRC20",
                        decimals: 6,
                        contractAddress: tronUsdt
                    ),
                    value: "1000000",
                    displayValue: "1"
                )
            ],
            sponsored: false,
            expiresAt: "2099-01-01T00:00:00Z"
        ),
        for: WaasAPI.PrepareTronContractCall.urlPath
    )
    try fixture.transport.enqueue(ExecuteResponse(status: .pending), for: WaasAPI.Execute.urlPath)

    _ = try await fixture.client.callTronContract(
        network: .nile,
        contract: tronUsdt,
        method: "transfer",
        args: [
            AbiArg(type: "address", value: .string(tronRecipient)),
            AbiArg(type: "uint256", value: .string("1"))
        ],
        selectFeeOption: .firstAvailable,
        waitForStatus: false
    )

    let execute = try fixture.transport.requestObject(for: WaasAPI.Execute.urlPath)
    let expectedIndexerRequest: NSDictionary = [
        "networks": ["tron:nile"],
        "filter": [
            "accountAddresses": [tronWalletAddress],
            "omitNativeBalances": true,
            "contractWhitelist": [tronUsdt]
        ],
        "omitMetadata": true
    ]
    #expect(fixture.indexerBackend.tronBalanceRequestPayloads == [expectedIndexerRequest])
    #expect(execute == (["txnId": "txn-usdt-fee", "feeOption": ["token": "USDT", "index": 0]] as NSDictionary))
}

@Test func TestTronSignsMessagesAndTypedDataWithoutEvmNetwork() async throws {
    let fixture = makeActiveWalletFixture()
    try fixture.transport.enqueue(SignMessageResponse(signature: "0xtron-signature"), for: WaasAPI.SignMessage.urlPath)
    try fixture.transport.enqueue(SignTypedDataResponse(signature: "0xtron-typed"), for: WaasAPI.SignTypedData.urlPath)
    let typedData: JSONValue = .object([
        "domain": .object([
            "name": .string("Example"),
            "chainId": .integer(3_448_148_188),
            "verifyingContract": .string(tronUsdt)
        ]),
        "types": .object(["Mail": .array([.object(["name": .string("to"), "type": .string("address")])])]),
        "primaryType": .string("Mail"),
        "message": .object(["to": .string(tronRecipient)])
    ])

    let messageSignature = try await fixture.client.signTronMessage(message: "hello")
    let typedDataSignature = try await fixture.client.signTronTypedData(typedData: typedData)

    let signMessage = try fixture.transport.requestObject(for: WaasAPI.SignMessage.urlPath)
    let signTypedData = try fixture.transport.requestObject(for: WaasAPI.SignTypedData.urlPath)
    let expectedTypedData: NSDictionary = [
        "domain": ["name": "Example", "chainId": 3_448_148_188, "verifyingContract": tronUsdt],
        "types": ["Mail": [["name": "to", "type": "address"]]],
        "primaryType": "Mail",
        "message": ["to": tronRecipient]
    ]
    #expect(messageSignature == "0xtron-signature")
    #expect(typedDataSignature == "0xtron-typed")
    #expect(signMessage == (["network": "", "walletId": "wallet-id", "message": "hello"] as NSDictionary))
    #expect(signTypedData["network"] as? String == "")
    #expect(signTypedData["walletId"] as? String == "wallet-id")
    #expect(signTypedData["typedData"] as? NSDictionary == expectedTypedData)
}

@Test func TestTronSignatureValidationUsesTronNetworkFamily() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        IsValidMessageSignatureResponse(isValid: true),
        for: WaasPublicAPI.IsValidMessageSignature.urlPath
    )
    try fixture.transport.enqueue(
        IsValidTypedDataSignatureResponse(isValid: false),
        for: WaasPublicAPI.IsValidTypedDataSignature.urlPath
    )

    let messageValid = try await fixture.client.isValidTronMessageSignature(
        walletAddress: tronWalletAddress,
        message: "hello",
        signature: "0xsig"
    )
    let typedDataValid = try await fixture.client.isValidTronTypedDataSignature(
        walletAddress: tronWalletAddress,
        typedData: .object(["primaryType": .string("Mail")]),
        signature: "0xsig"
    )

    let message = try fixture.transport.requestObject(for: WaasPublicAPI.IsValidMessageSignature.urlPath)
    let typedData = try fixture.transport.requestObject(for: WaasPublicAPI.IsValidTypedDataSignature.urlPath)
    let expectedMessage: NSDictionary = [
        "networkFamily": "tron",
        "walletAddress": tronWalletAddress,
        "message": "hello",
        "signature": "0xsig"
    ]
    let expectedTypedData: NSDictionary = [
        "networkFamily": "tron",
        "walletAddress": tronWalletAddress,
        "typedData": ["primaryType": "Mail"],
        "signature": "0xsig"
    ]
    #expect(messageValid)
    #expect(!typedDataValid)
    #expect(message == expectedMessage)
    #expect(typedData == expectedTypedData)
}

@Test(arguments: [
    (WalletType.ethereum, "0x9999999999999999999999999999999999999999"),
    (WalletType.solana, "4Nd1mYQbqjVU2aR7cJNPyqW9XjHnBYvWQd7ZxYxvT6uP")
])
func TestTronOperationsRejectNonTronWalletsBeforeAnyRequest(type: WalletType, address: String) async {
    let fixture = makeActiveWalletFixture(type: type, address: address)

    await expectValidationError(.walletSendTronTransaction) {
        try await fixture.client.sendTronTransaction(network: .nile, to: tronRecipient, value: "1")
    }
    await expectValidationError(.walletCallTronContract) {
        try await fixture.client.callTronContract(network: .nile, contract: tronUsdt, method: "transfer")
    }
    await expectValidationError(.walletSignTronMessage) {
        try await fixture.client.signTronMessage(message: "hello")
    }
    await expectValidationError(.walletSignTronTypedData) {
        try await fixture.client.signTronTypedData(typedData: .object([:]))
    }
    #expect(fixture.transport.totalRequestCount == 0)
}

@Test func TestEvmSolanaAndSmartSessionOperationsRejectTronWalletsBeforeAnyRequest() async {
    // A Tron address in hex form passes an address-shape check; the guard must use the stored type.
    let fixture = makeActiveWalletFixture(type: .tron, address: tronWalletHex)

    await expectValidationError(.walletSendTransaction) {
        try await fixture.client.sendTransaction(network: .polygon, to: tronWalletHex, value: "1")
    }
    await expectValidationError(.walletCallContract) {
        try await fixture.client.callContract(network: .polygon, contract: tronWalletHex, method: "transfer", args: nil)
    }
    await expectValidationError(.walletSignMessage) {
        try await fixture.client.signMessage(network: .polygon, message: "hello")
    }
    await expectValidationError(.walletSignTypedData) {
        try await fixture.client.signTypedData(network: .polygon, typedData: .object([:]))
    }
    await expectValidationError(.walletSignSolanaMessage) {
        try await fixture.client.signSolanaMessage(message: "hello")
    }
    await expectValidationError(.walletSendSolanaTransfer) {
        try await fixture.client.sendSolanaTransfer(network: .devnet, asset: "SOL", to: "recipient", amount: "1")
    }
    await expectValidationError(.walletAuthorizeRemoteAccess) {
        try await fixture.client.authorizeRemoteAccess(
            credentialId: "remote-credential",
            network: .polygon,
            grants: [.nativeTransfer(to: "0x2222222222222222222222222222222222222222", limit: "1")],
            expiresAt: "2099-01-01T00:00:00Z"
        )
    }
    #expect(fixture.transport.totalRequestCount == 0)
}

@Test func TestCreateWalletActivatesTronWalletThroughTronNetworkFamily() async throws {
    let fixture = makeActiveWalletFixture(type: .ethereum, address: "0x9999999999999999999999999999999999999999")
    try fixture.transport.enqueue(
        CreateWalletResponse(
            wallet: WaasWallet(id: "wallet-tron", networkFamily: .tron, keyOrigin: .enclave, address: tronWalletAddress)
        ),
        for: WaasAPI.CreateWallet.urlPath
    )

    let result = try await fixture.client.createWallet(walletType: .tron)

    let request = try fixture.transport.requestObject(for: WaasAPI.CreateWallet.urlPath)
    let expected = Wallet(id: "wallet-tron", type: .tron, address: tronWalletAddress, keyOrigin: .enclave)
    #expect(request["networkFamily"] as? String == "tron")
    #expect(result.wallet == expected)
    #expect(fixture.client.activeWallet == expected)
    #expect(fixture.client.walletId == "wallet-tron")
    #expect(try fixture.storedCredentials()?.wallet == expected)
}

@Test func TestImportWalletSealsTronPrivateKeyAndActivatesTronWallet() async throws {
    let importTransport = MockWaasTransport()
    let fixture = makeMockWalletClient(
        walletImportClient: WaasClient(baseURL: "https://wallet-import.test", transport: importTransport)
    )
    fixture.client.walletId = "wallet-main"
    fixture.client.activeWallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    fixture.client.sessionExpiresAt = "2099-01-01T00:00:00Z"
    fixture.client.sessionAuth = .email(OMSWalletEmailSessionAuth(email: "user@example.com"))
    let recipient = P256.KeyAgreement.PrivateKey()
    try importTransport.enqueue(
        WaasGenerated.GetRecipientKeyResponse(
            keyId: "recipient-key",
            publicKey: recipient.publicKey.derRepresentation.base64EncodedString()
        ),
        for: WaasAPI.GetRecipientKey.urlPath
    )
    try importTransport.enqueue(
        WaasGenerated.ImportWalletResponse(
            wallet: WaasWallet(id: "wallet-tron", networkFamily: .tron, keyOrigin: .imported, address: tronWalletAddress)
        ),
        for: WaasAPI.ImportWallet.urlPath
    )

    let result = try await fixture.client.importWallet(
        privateKey: .tron("0x" + String(repeating: "11", count: 32)),
        reference: "imported-tron"
    )

    let request = try importTransport.requestObject(for: WaasAPI.ImportWallet.urlPath)
    let expected = Wallet(id: "wallet-tron", type: .tron, address: tronWalletAddress, keyOrigin: .imported)
    #expect(request["networkFamily"] as? String == "tron")
    #expect(request["reference"] as? String == "imported-tron")
    #expect(result.wallet == expected)
    #expect(fixture.client.activeWallet == expected)
}

@Test func TestTronPrivateKeyImportUsesSecp256k1Validation() throws {
    let key = String(repeating: "11", count: 32)
    #expect(try WalletImportValidation.plaintext(.tron(" 0x\(key)\n")) == Data("0x\(key)".utf8))
    #expect(try WalletImportValidation.plaintext(.tron(key)) == Data(key.utf8))
    let one = Data(repeating: 0, count: 31) + Data([1])
    #expect(try WalletImportValidation.plaintext(.tronBytes(one)) == one)

    let cases: [(WalletImportPrivateKey, String)] = [
        (.tron("0x1234"), "Tron privateKey must be 32 bytes or 64 hexadecimal characters"),
        (.tronBytes(Data(repeating: 1, count: 31)), "Tron privateKey must contain exactly 32 bytes"),
        (.tronBytes(Data(repeating: 0, count: 32)), "Tron privateKey is outside the valid secp256k1 scalar range"),
        (
            .tron("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"),
            "Tron privateKey is outside the valid secp256k1 scalar range"
        ),
        (.ethereum("0x1234"), "Ethereum privateKey must be 32 bytes or 64 hexadecimal characters")
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
}

@Test func TestTronNetworksUseWaasNetworkIdentifiers() {
    #expect(TronNetwork.allCases == [.mainnet, .nile])
    #expect(TronNetworks.mainnet.rawValue == "tron:mainnet")
    #expect(TronNetworks.nile.rawValue == "tron:nile")
    #expect(WalletType(wireValue: "tron") == .tron)
    #expect(WalletType.tron.wireValue == "tron")
}
