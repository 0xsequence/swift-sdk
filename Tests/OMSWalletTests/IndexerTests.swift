import Foundation
import Testing
@testable import OMSWallet

@Test func TestSupportedNetworks() throws {
    #expect(Network.supportedNetworks == [
        .mainnet,
        .sepolia,
        .polygon,
        .amoy,
        .arbitrum,
        .arbitrumSepolia,
        .optimism,
        .optimismSepolia,
        .base,
        .baseSepolia,
        .bsc,
        .bscTestnet,
        .arbitrumNova,
        .avalanche,
        .avalancheTestnet,
        .katana,
    ])

    #expect(Network.findById(8453) == .base)
    #expect(Network.findById(747474) == .katana)
    #expect(Network.findByName("optimism-sepolia") == .optimismSepolia)
    #expect(Network.findByName("amoy") == .amoy)
    #expect(Network.findByName(" AMOY ") == .amoy)
    #expect(Network.findByName("polygonamoy") == nil)
    #expect(Network.findByName("polygonAmoy") == nil)
    #expect(Network(rawValue: "arbitrum-sepolia") == .arbitrumSepolia)
    #expect(Network(rawValue: "amoy") == .amoy)

    #expect(Network.polygon.displayName == "Polygon")
    #expect(Network.polygon.description == "Polygon")
    #expect(Network.polygon.id == 137)
    #expect(Network.polygon.name == "polygon")
    #expect(Network.polygon.nativeTokenSymbol == "POL")
    #expect(Network.polygon.explorerUrl == "https://polygonscan.com")
    #expect(Network.amoy.name == "amoy")
    #expect(Network.amoy.id == 80002)
    #expect(Network.amoy.displayName == "Polygon Amoy")
    #expect(Network.findById(80002) == .amoy)
}

@Test func TestPublishableKeyRoutingDerivesProjectAndApiUrls() throws {
    let routes = [
        (
            "pk_dev_sdbx_project_key",
            "https://sandbox-api.dev.polygon-dev.technology",
            [String(repeating: "0", count: 96)]
        ),
        (
            "pk_dev_live_project_key",
            "https://api.dev.polygon-dev.technology",
            [String(repeating: "0", count: 96)]
        ),
        (
            "pk_stg_sdbx_project_key",
            "https://sandbox-api.stg.polygon-dev.technology",
            ["3d21c70519a0ea3d5e6af43c5323234d90755d1ca08431064bd9687ddde4a4788a0a4736701513eee6008f1ec17e0d23"]
        ),
        (
            "pk_stg_live_project_key",
            "https://api.stg.polygon-dev.technology",
            ["3d21c70519a0ea3d5e6af43c5323234d90755d1ca08431064bd9687ddde4a4788a0a4736701513eee6008f1ec17e0d23"]
        ),
        (
            "pk_sdbx_project_key",
            "https://sandbox-api.polygon.technology",
            [
                "1935cbc713f0b43060315689e87285f6ba76bcf06f26d0719735e8d674b71e0eff71dcf77fe90ab32870ef3c954973b7",
                "66d0d20073ec8549b6eb1cd3cd53311495225ec79d68f168ab734b24a69a8ed0f890f85ff31d5f0a79486a4e3a303b3c"
            ]
        ),
        (
            "pk_live_project_key",
            "https://api.polygon.technology",
            [
                "1935cbc713f0b43060315689e87285f6ba76bcf06f26d0719735e8d674b71e0eff71dcf77fe90ab32870ef3c954973b7",
                "66d0d20073ec8549b6eb1cd3cd53311495225ec79d68f168ab734b24a69a8ed0f890f85ff31d5f0a79486a4e3a303b3c"
            ]
        )
    ]

    for (publishableKey, apiUrl, walletImportPcr0s) in routes {
        let parsedKey = try parsePublishableKey(publishableKey)
        #expect(parsedKey.projectId == "prj_project")
        #expect(parsedKey.walletApiUrl == apiUrl)
        #expect(parsedKey.indexerGatewayUrl == "\(apiUrl)/v1/IndexerGateway/")
        #expect(parsedKey.solanaIndexerGatewayUrl == "\(apiUrl)/v1/SolanaIndexerGateway/")
        #expect(parsedKey.tronIndexerGatewayUrl == "\(apiUrl)/v1/TronIndexerGateway/")
        #expect(parsedKey.environment().tronIndexerGatewayUrl == "\(apiUrl)/v1/TronIndexerGateway/")
        #expect(parsedKey.walletImportTrustedPcr0s == Set(walletImportPcr0s))

        let oms = try OMSWallet(publishableKey: publishableKey)
        #expect(oms.wallet.projectId == "prj_project")
    }
}

@Test func TestPublishableKeyRoutingRejectsInvalidKeys() throws {
    for publishableKey in [
        "pk_test_sdbx_project_key",
        "pk_dev_sdbx_project",
        "pk_dev_sdbx__key",
        "pk_dev_sdbx_project_"
    ] {
        do {
            _ = try OMSWallet(publishableKey: publishableKey)
            #expect(Bool(false), "Expected invalid publishable key")
        } catch let error as OMSWalletError {
            #expect(error.code == .validationError)
            #expect(error.operation == nil)
            #expect(error.localizedDescription == "Invalid publishableKey.")
        } catch {
            #expect(Bool(false), "Expected OMSWalletError")
        }
    }
}

@Test func TestIndexerCancelledRequestPreservesCancellation() async throws {
    let recorder = IndexerRequestRecorder(transportError: URLError(.cancelled))
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getBalances(
            GetBalancesParams(
                walletAddress: "0xwallet",
                networks: [.polygon],
                includeMetadata: false
            )
        )
        #expect(Bool(false), "Expected cancellation")
    } catch is CancellationError {
    } catch {
        #expect(Bool(false), "Expected CancellationError, got \(error)")
    }
}

@Test func TestGetBalancesEncodesGatewayScopeFiltersAndHeaders() async throws {
    let recorder = IndexerRequestRecorder()
    let client = makeRecordingIndexerClient(recorder: recorder)

    _ = try await client.getBalances(
        GetBalancesParams(
            walletAddress: "0xwallet",
            networks: [.polygon, .base],
            contractAddresses: ["0xTokenContract"],
            includeMetadata: false,
            omitPrices: true,
            tokenIds: ["123"],
            contractStatus: .verified,
            page: TokenBalancesPageRequest(page: 2, pageSize: 100)
        )
    )

    let request = try #require(recorder.recordedRequest())
    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let filter = try #require(payload["filter"] as? [String: Any])
    let page = try #require(payload["page"] as? [String: Any])

    #expect(request.url?.path == "/v1/IndexerGateway/GetTokenBalancesDetails")
    #expect(request.value(forHTTPHeaderField: "Api-Key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Webrpc")?.contains("sequence-indexer@v0.4.0") == true)
    #expect(payload["chainIds"] as? [Int] == [137, 8453])
    #expect(payload["networkType"] == nil)
    #expect(payload["omitMetadata"] as? Bool == true)
    #expect(filter["accountAddresses"] as? [String] == ["0xwallet"])
    #expect(filter["contractWhitelist"] as? [String] == ["0xTokenContract"])
    #expect(filter["contractStatus"] as? String == "VERIFIED")
    #expect(filter["omitNativeBalances"] as? Bool == false)
    #expect(filter["omitPrices"] as? Bool == true)
    #expect(filter["tokenIDs"] as? [String] == ["123"])
    #expect(page["page"] as? Int == 2)
    #expect(page["pageSize"] as? Int == 100)
}

@Test func TestGetSolanaBalancesUsesSolanaGatewayAndDecodesStrictAssets() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"{"balances":[{"network":"solana:mainnet","accountAddress":"solana-wallet","assetType":"native","name":"Solana","symbol":"SOL","decimals":9,"balance":"4679287","formattedBalance":"0.004679287","imageUrl":"","metadataUri":"","verificationStatus":"unknown","verificationSource":"none"},{"network":"solana:mainnet","accountAddress":"solana-wallet","assetType":"fungible-token","tokenProgram":"spl-token","mintAddress":"usdc-mint","name":"USD Coin","symbol":"USDC","decimals":6,"balance":"4208117429","formattedBalance":"4208.117429","verificationStatus":"verified","verificationSource":"jupiter"}],"errors":[{"network":"solana:devnet","reason":"RPC unavailable"}]}"#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    let result = try await client.getSolanaBalances(
        GetSolanaBalancesParams(
            walletAddress: "solana-wallet",
            includeMetadata: false,
            omitNativeBalances: false,
            mintAddresses: ["usdc-mint"],
            excludedMintAddresses: ["spam-mint"]
        )
    )

    let request = try #require(recorder.recordedRequest())
    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let filter = try #require(payload["filter"] as? [String: Any])
    #expect(request.url?.path == "/v1/SolanaIndexerGateway/GetTokenBalancesDetails")
    #expect(request.value(forHTTPHeaderField: "Webrpc")?.contains("solana-indexer-gateway@v1") == true)
    #expect(payload["networks"] as? [String] == ["solana:mainnet", "solana:devnet"])
    #expect(payload["omitMetadata"] as? Bool == true)
    #expect(filter["contractWhitelist"] as? [String] == ["usdc-mint"])
    #expect(filter["contractBlacklist"] as? [String] == ["spam-mint"])
    #expect(result.balances.count == 2)
    guard case .fungibleToken(let token) = result.balances[1] else {
        Issue.record("Expected fungible token balance")
        return
    }
    #expect(token.mintAddress == "usdc-mint")
    #expect(result.errors.first?.network == .devnet)

    let native = result.balances[0]
    let fungible = result.balances[1]
    #expect(native.network == .mainnet)
    #expect(native.accountAddress == "solana-wallet")
    #expect(native.name == "Solana")
    #expect(native.symbol == "SOL")
    #expect(native.decimals == 9)
    #expect(native.balance == "4679287")
    #expect(native.formattedBalance == "0.004679287")
    #expect(native.imageUrl == nil)
    #expect(native.metadataUri == nil)
    #expect(native.verificationStatus == .unknown)
    #expect(native.verificationSource == SolanaVerificationSource.none)
    #expect(native.priceUSD == nil)
    #expect(native.balanceUSD == nil)
    #expect(fungible.symbol == "USDC")
    #expect(fungible.decimals == 6)
    #expect(fungible.balance == "4208117429")
    #expect(fungible.verificationStatus == .verified)
    #expect(fungible.verificationSource == .jupiter)
}

@Test func TestGetTronBalancesUsesTronGatewayAndDecodesStrictAssets() async throws {
    let wallet = "TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H"
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"""
            {
              "balances": [
                {
                  "network": "tron:nile",
                  "accountAddress": "TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H",
                  "assetType": "fungible-token",
                  "contractAddress": "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf",
                  "tokenStandard": "trc20",
                  "name": "Tether USD",
                  "symbol": "USDT",
                  "decimals": 6,
                  "balance": "999000000",
                  "formattedBalance": "999",
                  "imageUrl": null,
                  "metadataUri": null,
                  "verificationStatus": "unknown",
                  "verificationSource": "none",
                  "priceUSD": null,
                  "balanceUSD": null
                },
                {
                  "network": "tron:nile",
                  "accountAddress": "TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H",
                  "assetType": "native",
                  "contractAddress": null,
                  "tokenStandard": null,
                  "name": "Tron",
                  "symbol": "TRX",
                  "decimals": 6,
                  "balance": "983121000",
                  "formattedBalance": "983.121",
                  "imageUrl": "",
                  "metadataUri": null,
                  "verificationStatus": "unknown",
                  "verificationSource": "none",
                  "priceUSD": "0.27",
                  "balanceUSD": "265.44"
                }
              ],
              "errors": [{"network": "tron:mainnet", "reason": "RPC unavailable"}],
              "coverage": {"network": "tron:nile", "tokenSymbols": ["USDT"], "nativeIncluded": true},
              "coverages": [{"network": "tron:nile", "tokenSymbols": ["USDT"], "nativeIncluded": true}]
            }
            """#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    let result = try await client.getTronBalances(
        GetTronBalancesParams(
            walletAddress: wallet,
            networks: [.nile],
            includeMetadata: false,
            omitNativeBalances: false,
            contractAddresses: ["TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"],
            excludedContractAddresses: ["TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"]
        )
    )

    let request = try #require(recorder.recordedRequest())
    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? NSDictionary)
    let expectedPayload: NSDictionary = [
        "networks": ["tron:nile"],
        "filter": [
            "accountAddresses": [wallet],
            "omitNativeBalances": false,
            "contractWhitelist": ["TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf"],
            "contractBlacklist": ["TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"]
        ],
        "omitMetadata": true
    ]
    #expect(request.url?.path == "/v1/TronIndexerGateway/GetTokenBalancesDetails")
    #expect(request.value(forHTTPHeaderField: "Api-Key") == "test-key")
    #expect(
        request.value(forHTTPHeaderField: "Webrpc")
            == "webrpc@v0.31.2;gen-swift@v0.1.2;tron-indexer-gateway@v1"
    )
    #expect(payload == expectedPayload)
    #expect(result.status == 200)
    #expect(result.balances.count == 2)
    guard case .fungibleToken(let token) = result.balances[0],
          case .native(let native) = result.balances[1] else {
        Issue.record("Expected a TRC-20 balance followed by a native balance")
        return
    }
    #expect(token.network == .nile)
    #expect(token.accountAddress == wallet)
    #expect(token.tokenStandard == .trc20)
    #expect(token.contractAddress == "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf")
    #expect(token.symbol == "USDT")
    #expect(token.decimals == 6)
    #expect(token.balance == "999000000")
    #expect(token.formattedBalance == "999")
    #expect(token.imageUrl == nil)
    #expect(token.priceUSD == nil)
    #expect(token.verificationStatus == .unknown)
    #expect(token.verificationSource == "none")
    #expect(native.symbol == "TRX")
    #expect(native.balance == "983121000")
    #expect(native.imageUrl == nil)
    #expect(native.metadataUri == nil)
    #expect(native.priceUSD == "0.27")
    #expect(native.balanceUSD == "265.44")
    let tokenBalance = result.balances[0]
    let nativeBalance = result.balances[1]
    #expect(tokenBalance.network == .nile)
    #expect(tokenBalance.accountAddress == wallet)
    #expect(tokenBalance.name == "Tether USD")
    #expect(tokenBalance.symbol == "USDT")
    #expect(tokenBalance.decimals == 6)
    #expect(tokenBalance.balance == "999000000")
    #expect(tokenBalance.formattedBalance == "999")
    #expect(tokenBalance.verificationStatus == .unknown)
    #expect(tokenBalance.verificationSource == "none")
    #expect(nativeBalance.symbol == "TRX")
    #expect(nativeBalance.imageUrl == nil)
    #expect(nativeBalance.metadataUri == nil)
    #expect(nativeBalance.priceUSD == "0.27")
    #expect(nativeBalance.balanceUSD == "265.44")
    #expect(result.errors.map(\.network) == [.mainnet])
    #expect(result.errors.map(\.reason) == ["RPC unavailable"])
}

@Test func TestGetTronBalancesDefaultsToSupportedNetworks() async throws {
    let recorder = IndexerRequestRecorder(responseBody: Data(#"{"balances":[],"errors":[]}"#.utf8))
    let client = makeRecordingIndexerClient(recorder: recorder)

    _ = try await client.getTronBalances(
        GetTronBalancesParams(walletAddress: "TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H")
    )

    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? NSDictionary)
    let expectedPayload: NSDictionary = [
        "networks": ["tron:mainnet", "tron:nile"],
        "filter": ["accountAddresses": ["TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H"]],
        "omitMetadata": false
    ]
    #expect(payload == expectedPayload)
}

@Test(arguments: [
    #"{"balances":[{"network":"tron:shasta","accountAddress":"T","assetType":"native","name":"Tron","symbol":"TRX","decimals":6,"balance":"0","formattedBalance":"0","verificationStatus":"unknown","verificationSource":"none"}],"errors":[]}"#,
    #"{"balances":[],"errors":[{"network":"tron:shasta","reason":"down"}]}"#,
    #"{"balances":[{"network":"tron:nile","accountAddress":"T","assetType":"native","contractAddress":"TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf","name":"Tron","symbol":"TRX","decimals":6,"balance":"0","formattedBalance":"0","verificationStatus":"unknown","verificationSource":"none"}],"errors":[]}"#,
    #"{"balances":[{"network":"tron:nile","accountAddress":"T","assetType":"fungible-token","tokenStandard":"trc10","contractAddress":"1002000","name":"BTT","symbol":"BTT","decimals":6,"balance":"0","formattedBalance":"0","verificationStatus":"unknown","verificationSource":"none"}],"errors":[]}"#,
    #"{"balances":[],"errors":null}"#
])
func TestGetTronBalancesRejectsInvalidResponses(responseBody: String) async throws {
    let recorder = IndexerRequestRecorder(responseBody: Data(responseBody.utf8))
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getTronBalances(
            GetTronBalancesParams(walletAddress: "TW39NT9SCCv7aomYYXgh4wcUWag4XtVe2H")
        )
        Issue.record("Expected an invalid Tron balances response")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .indexerGetTronBalances)
        #expect(error.status == 200)
    }
}

@Test func TestGetTronBalancesSurfacesGatewayRequestErrors() async throws {
    let recorder = IndexerRequestRecorder(
        statusCode: 400,
        responseBody: Data(
            #"{"code":-4,"message":"invalid Tron address: 0x1234","name":"WebrpcBadRequest","status":400}"#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getTronBalances(GetTronBalancesParams(walletAddress: "0x1234"))
        Issue.record("Expected a Tron gateway HTTP error")
    } catch let error as OMSWalletError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetTronBalances)
        #expect(error.status == 400)
        #expect(error.retryable == false)
        #expect(error.upstreamError?.service == .indexer)
        #expect(error.upstreamError?.status == 400)
        #expect(error.upstreamError?.message == "invalid Tron address: 0x1234")
    }
}

@Test func TestGetTransactionHistoryEncodesGatewayFiltersAndDecodesTransactions() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"""
            {
              "page": {"page": 0, "pageSize": 40, "more": false},
              "transactions": [
                {
                  "chainId": 80002,
                  "results": [
                    {
                      "txnHash": "0xtxn",
                      "blockNumber": 123,
                      "blockHash": "0xblock",
                      "chainId": 80002,
                      "metaTxnID": "meta-1",
                      "timestamp": "2026-01-01T00:00:00Z",
                      "transfers": [
                        {
                          "transferType": "SEND",
                          "contractAddress": "0xcontract",
                          "contractType": "ERC721",
                          "from": "0xwallet",
                          "to": "0xrecipient",
                          "tokenIds": ["7"],
                          "amounts": ["1"],
                          "logIndex": 0,
                          "tokenMetadata": {
                            "7": {
                              "chainId": 80002,
                              "contractAddress": "0xcontract",
                              "tokenId": "7",
                              "source": "metadata",
                              "name": "Token 7",
                              "attributes": [],
                              "status": "available"
                            }
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    let result = try await client.getTransactionHistory(
        GetTransactionHistoryParams(
            walletAddress: "0xwallet",
            networkType: .all,
            contractAddresses: ["0xcontract"],
            transactionHashes: ["0xtxn"],
            metaTransactionIds: ["meta-1"],
            fromBlock: 1,
            toBlock: 200,
            tokenId: "7",
            includeMetadata: true,
            omitPrices: true
        )
    )

    let body = try #require(recorder.recordedBody())
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let filter = try #require(payload["filter"] as? [String: Any])
    let transaction = try #require(result.transactions.first)
    let transfer = try #require(transaction.transfers.first)

    #expect(recorder.recordedRequest()?.url?.path == "/v1/IndexerGateway/GetTransactionHistory")
    #expect(payload["networkType"] as? String == "ALL")
    #expect(payload["chainIds"] == nil)
    #expect(payload["includeMetadata"] as? Bool == true)
    #expect(filter["accountAddresses"] as? [String] == ["0xwallet"])
    #expect(filter["contractAddresses"] as? [String] == ["0xcontract"])
    #expect(filter["transactionHashes"] as? [String] == ["0xtxn"])
    #expect(filter["metaTransactionIDs"] as? [String] == ["meta-1"])
    #expect(filter["fromBlock"] as? Int == 1)
    #expect(filter["toBlock"] as? Int == 200)
    #expect(filter["tokenID"] as? String == "7")
    #expect(filter["omitPrices"] as? Bool == true)
    #expect(transaction.metaTxnId == "meta-1")
    #expect(transfer.tokenIds == ["7"])
    #expect(transfer.tokenMetadata?["7"]?.tokenId == "7")
}

@Test func TestTokenBalanceDecodesIndexerMetadataFields() throws {
    let fixture = Data(
        #"""
        {
          "contractType": "ERC721",
          "contractAddress": "0xcontract",
          "accountAddress": "0xwallet",
          "tokenID": "123",
          "balance": "1",
          "balanceUSD": "12.34",
          "priceUSD": "12.34",
          "priceUpdatedAt": "2026-01-01T00:00:00Z",
          "blockHash": "0xhash",
          "blockNumber": 12345,
          "chainId": 137,
          "uniqueCollectibles": "1",
          "isSummary": false,
          "contractInfo": {
            "chainId": 137,
            "address": "0xcontract",
            "source": "metadata",
            "name": "Example Token",
            "type": "ERC721",
            "symbol": "EXM",
            "decimals": 0,
            "logoURI": "https://example.com/logo.png",
            "deployed": true,
            "bytecodeHash": "0xbytecode",
            "extensions": {"verified": true},
            "updatedAt": "2026-01-02T00:00:00Z",
            "queuedAt": null,
            "status": "available"
          },
          "tokenMetadata": {
            "chainId": 137,
            "contractAddress": "0xcontract",
            "tokenId": "123",
            "source": "metadata",
            "name": "Example NFT",
            "description": "Example description",
            "image": "ipfs://image",
            "video": "ipfs://video",
            "audio": "ipfs://audio",
            "properties": {"rarity": "rare"},
            "attributes": [{"trait_type": "Level", "value": 7}],
            "image_data": "<svg></svg>",
            "external_url": "https://example.com/token/123",
            "background_color": "ffffff",
            "animation_url": "ipfs://animation",
            "decimals": 0,
            "updatedAt": "2026-01-03T00:00:00Z",
            "assets": [
              {
                "id": 1,
                "collectionId": 2,
                "tokenId": "asset-token",
                "url": "https://example.com/asset.png",
                "metadataField": "image",
                "name": "Asset",
                "filesize": 123456,
                "mimeType": "image/png",
                "width": 640,
                "height": 480,
                "updatedAt": "2026-01-04T00:00:00Z"
              }
            ],
            "status": "available",
            "queuedAt": null,
            "lastFetched": "2026-01-05T00:00:00Z"
          }
        }
        """#.utf8
    )

    let balance = try JSONDecoder().decode(ContractTokenBalance.self, from: fixture)
    let contractInfo = try #require(balance.contractInfo)
    let tokenMetadata = try #require(balance.tokenMetadata)
    let asset = try #require(tokenMetadata.assets?.first)

    #expect(balance.tokenId == "123")
    #expect(balance.balanceUSD == "12.34")
    #expect(balance.priceUSD == "12.34")
    #expect(balance.priceUpdatedAt == "2026-01-01T00:00:00Z")
    #expect(balance.uniqueCollectibles == "1")
    #expect(balance.isSummary == false)
    #expect(contractInfo.symbol == "EXM")
    #expect(contractInfo.decimals == 0)
    #expect(contractInfo.logoURI == "https://example.com/logo.png")
    #expect(tokenMetadata.tokenId == "123")
    #expect(tokenMetadata.name == "Example NFT")
    #expect(tokenMetadata.imageData == "<svg></svg>")
    #expect(tokenMetadata.externalUrl == "https://example.com/token/123")
    #expect(asset.tokenId == "asset-token")
    #expect(asset.url == "https://example.com/asset.png")

    if case .bool(true)? = contractInfo.extensions["verified"] {
    } else {
        #expect(Bool(false), "Expected contractInfo.extensions.verified to decode")
    }

    if case .string("rare")? = tokenMetadata.properties?["rarity"] {
    } else {
        #expect(Bool(false), "Expected tokenMetadata.properties.rarity to decode")
    }
}

@Test func TestGetBalancesRejectsMissingRequiredContractBalanceFields() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"{"page":{"page":0,"pageSize":40,"more":false},"nativeBalances":[],"balances":[{"chainId":137,"results":[{"contractType":"ERC20","contractAddress":"0xtoken","accountAddress":"0xwallet","tokenID":"0","balance":"1","blockNumber":1,"chainId":137}]}]}"#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getBalances(GetBalancesParams(walletAddress: "0xwallet"))
        #expect(Bool(false), "Expected an invalid response error")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .indexerGetBalances)
    }
}

@Test func TestGetBalancesRejectsMissingOrNullRequiredResultContainers() async throws {
    let responseBodies = [
        #"{"balances":[]}"#,
        #"{"nativeBalances":null,"balances":[]}"#,
        #"{"nativeBalances":[{"chainId":137}],"balances":[]}"#,
        #"{"nativeBalances":[{"chainId":137,"results":null}],"balances":[]}"#
    ]

    for responseBody in responseBodies {
        let recorder = IndexerRequestRecorder(responseBody: Data(responseBody.utf8))
        let client = makeRecordingIndexerClient(recorder: recorder)

        do {
            _ = try await client.getBalances(GetBalancesParams(walletAddress: "0xwallet"))
            #expect(Bool(false), "Expected an invalid response error for \(responseBody)")
        } catch let error as OMSWalletError {
            #expect(error.code == .invalidResponse)
            #expect(error.operation == .indexerGetBalances)
        }
    }
}

@Test func TestGetTransactionHistoryRejectsMissingTransfers() async throws {
    let recorder = IndexerRequestRecorder(
        responseBody: Data(
            #"{"transactions":[{"chainId":137,"results":[{"txnHash":"0xtxn","blockNumber":1,"blockHash":"0xblock","chainId":137,"timestamp":"2026-01-01T00:00:00Z"}]}]}"#.utf8
        )
    )
    let client = makeRecordingIndexerClient(recorder: recorder)

    do {
        _ = try await client.getTransactionHistory(GetTransactionHistoryParams(walletAddress: "0xwallet"))
        #expect(Bool(false), "Expected an invalid response error")
    } catch let error as OMSWalletError {
        #expect(error.code == .invalidResponse)
        #expect(error.operation == .indexerGetTransactionHistory)
    }
}

@Test func TestGetTransactionHistoryRejectsMissingOrNullRequiredResultContainers() async throws {
    let responseBodies = [
        #"{}"#,
        #"{"transactions":null}"#,
        #"{"transactions":[{"chainId":137}]}"#,
        #"{"transactions":[{"chainId":137,"results":null}]}"#
    ]

    for responseBody in responseBodies {
        let recorder = IndexerRequestRecorder(responseBody: Data(responseBody.utf8))
        let client = makeRecordingIndexerClient(recorder: recorder)

        do {
            _ = try await client.getTransactionHistory(GetTransactionHistoryParams(walletAddress: "0xwallet"))
            #expect(Bool(false), "Expected an invalid response error for \(responseBody)")
        } catch let error as OMSWalletError {
            #expect(error.code == .invalidResponse)
            #expect(error.operation == .indexerGetTransactionHistory)
        }
    }
}

@Test func TestIndexerNonSuccessResponsesThrowOmsHttpError() async throws {
    let tokenBalancesRecorder = IndexerRequestRecorder(
        statusCode: 500,
        responseBody: Data(#"{"msg":"gateway unavailable"}"#.utf8)
    )
    let tokenBalancesClient = makeRecordingIndexerClient(recorder: tokenBalancesRecorder)

    do {
        _ = try await tokenBalancesClient.getBalances(
            GetBalancesParams(
                walletAddress: "0xwallet",
                networks: [.polygon],
                includeMetadata: true
            )
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OMSWalletError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetBalances)
        #expect(error.status == 500)
        #expect(error.retryable == true)
        #expect(error.localizedDescription == "gateway unavailable")
    } catch {
        #expect(Bool(false), "Expected OMSWalletError")
    }

    let historyRecorder = IndexerRequestRecorder(
        statusCode: 404,
        responseBody: Data(#"{"cause":"not found"}"#.utf8)
    )
    let historyClient = makeRecordingIndexerClient(recorder: historyRecorder)

    do {
        _ = try await historyClient.getTransactionHistory(
            GetTransactionHistoryParams(
                walletAddress: "0xwallet",
                networks: [.polygon]
            )
        )
        #expect(Bool(false), "Expected indexer HTTP error")
    } catch let error as OMSWalletError {
        #expect(error.code == .httpError)
        #expect(error.operation == .indexerGetTransactionHistory)
        #expect(error.status == 404)
        #expect(error.retryable == false)
        #expect(error.localizedDescription == "indexer.getTransactionHistory failed with HTTP 404")
    } catch {
        #expect(Bool(false), "Expected OMSWalletError")
    }
}

@available(macOS 12.0, iOS 15.0, *)
func makeRecordingIndexerClient(recorder: IndexerRequestRecorder) -> IndexerClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1

    let host = RecordingURLProtocol.register(recorder: recorder)

    let session = URLSession(configuration: configuration)
    let httpClient = HttpClient(session: session)
    let environment = OMSWalletEnvironment(
        walletApiUrl: "https://wallet.example.test",
        indexerGatewayUrl: "https://\(host)/v1/IndexerGateway/",
        solanaIndexerGatewayUrl: "https://\(host)/v1/SolanaIndexerGateway/",
        tronIndexerGatewayUrl: "https://\(host)/v1/TronIndexerGateway/"
    )

    return IndexerClient(
        publishableKey: "test-key",
        environment: environment,
        client: httpClient
    )
}

final class IndexerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    let statusCode: Int
    let responseBody: Data
    let transportError: (any Error)?
    private var body: Data?
    private var request: URLRequest?

    init(
        statusCode: Int = 200,
        responseBody: Data = Data(#"{"page":{"page":0,"pageSize":40,"more":false},"nativeBalances":[],"balances":[]}"#.utf8),
        transportError: (any Error)? = nil
    ) {
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.transportError = transportError
    }

    func record(request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
        self.body = body
    }

    func recordedBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    func recordedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordersByHost: [String: IndexerRequestRecorder] = [:]

    static func register(recorder: IndexerRequestRecorder) -> String {
        let host = "indexer-\(UUID().uuidString).test"
        lock.lock()
        defer { lock.unlock() }
        recordersByHost[host] = recorder
        return host
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let recorder = Self.recorder(for: request)
        recorder?.record(request: request, body: Self.bodyData(for: request))

        if let error = recorder?.transportError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: recorder?.statusCode ?? 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = recorder?.responseBody ?? Data()

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func recorder(for request: URLRequest) -> IndexerRequestRecorder? {
        guard let host = request.url?.host else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let recorder = recordersByHost[host] {
            return recorder
        }
        return recordersByHost.first { host.hasSuffix("-\($0.key)") }?.value
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}
