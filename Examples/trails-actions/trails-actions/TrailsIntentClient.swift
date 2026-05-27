import Foundation

struct RawQuoteIntentResponse {
    let intent: WebRPCJSONValue
    let depositTransaction: ParsedIntentDepositTransaction
    let outputRaw: String

    init(json: WebRPCJSONValue) throws {
        guard case .object(let root) = json,
              let intent = root["intent"],
              case .object(let intentObject) = intent,
              case .object(let depositObject) = intentObject["depositTransaction"] else {
            throw TrailsDemoError(message: "Trails quote returned an incomplete intent.")
        }

        guard let chainID = jsonUInt64(depositObject["chainId"]) ?? jsonUInt64(intentObject["originChainId"]),
              let to = jsonString(depositObject["to"]) else {
            throw TrailsDemoError(message: "Trails quote returned an incomplete deposit transaction.")
        }

        guard case .object(let quoteObject) = intentObject["quote"],
              let outputRaw = jsonString(quoteObject["toAmountMin"]) ?? jsonString(quoteObject["toAmount"]) else {
            throw TrailsDemoError(message: "Trails quote did not include an output amount.")
        }

        self.intent = intent
        self.depositTransaction = ParsedIntentDepositTransaction(
            to: to,
            data: jsonString(depositObject["data"]) ?? "0x",
            value: jsonString(depositObject["value"]) ?? "0",
            chainID: chainID
        )
        self.outputRaw = outputRaw
    }
}

struct ParsedIntentDepositTransaction {
    let to: String
    let data: String
    let value: String
    let chainID: UInt64
}

struct TrailsIntentClient: Sendable {
    let baseURL: String
    let transport: any WebRPCTransport
    let headers: @Sendable () -> [String: String]

    init(
        baseURL: String,
        transport: any WebRPCTransport = URLSessionWebRPCTransport(),
        headers: @escaping @Sendable () -> [String: String] = { [:] }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.headers = headers
    }

    func quoteIntent(_ request: QuoteIntentRequest) async throws -> RawQuoteIntentResponse {
        let body = try TrailsApiTrailsAPI.QuoteIntent.encodeRequest(request)
        return try await executeWebRPC(
            baseURL: baseURL,
            urlPath: TrailsApiTrailsAPI.QuoteIntent.urlPath,
            body: body,
            transport: transport,
            headers: requestHeaders,
            decodeSuccess: { data, decoder in
                try RawQuoteIntentResponse(json: decoder.decode(WebRPCJSONValue.self, from: data))
            }
        )
    }

    func commitIntent(_ intent: WebRPCJSONValue) async throws -> String {
        let body = try WebRPCJSON.makeEncoder().encode(
            WebRPCJSONValue.object(["intent": intent])
        )

        return try await executeWebRPC(
            baseURL: baseURL,
            urlPath: TrailsApiTrailsAPI.CommitIntent.urlPath,
            body: body,
            transport: transport,
            headers: requestHeaders,
            decodeSuccess: { data, decoder in
                let json = try decoder.decode(WebRPCJSONValue.self, from: data)
                guard case .object(let object) = json,
                      let intentID = jsonString(object["intentId"]) else {
                    throw TrailsDemoError(message: "Trails commit did not return an intent id.")
                }
                return intentID
            }
        )
    }

    func executeIntent(intentID: String, depositTransactionHash: String?) async throws {
        var request = ["intentId": WebRPCJSONValue.string(intentID)]
        if let depositTransactionHash {
            request["depositTransactionHash"] = .string(depositTransactionHash)
        }

        let body = try WebRPCJSON.makeEncoder().encode(WebRPCJSONValue.object(request))
        try await executeWebRPC(
            baseURL: baseURL,
            urlPath: TrailsApiTrailsAPI.ExecuteIntent.urlPath,
            body: body,
            transport: transport,
            headers: requestHeaders,
            decodeSuccess: { data, decoder in
                _ = try decoder.decode(WebRPCJSONValue.self, from: data)
            }
        )
    }

    private var requestHeaders: [String: String] {
        var requestHeaders = headers()
        requestHeaders[WEBRPC_HEADER] = WEBRPC_HEADER_VALUE
        return requestHeaders
    }
}

private func jsonUInt64(_ value: WebRPCJSONValue?) -> UInt64? {
    switch value {
    case .integer(let integer):
        return integer >= 0 ? UInt64(integer) : nil
    case .unsignedInteger(let integer):
        return integer
    case .number(let number):
        guard number.isFinite, number >= 0 else { return nil }
        return UInt64(number)
    case .string(let string):
        return UInt64(string)
    case .object, .array, .bool, .null, .none:
        return nil
    }
}
