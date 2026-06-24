import Foundation

@available(macOS 12.0, iOS 15.0, *)
struct SignedWaasTransport: WebRPCTransport {
    public let session: URLSession

    private let client: HttpClient
    private let publishableKey: String
    private let scope: String
    private let signer: any CredentialSigner

    public init(publishableKey: String,
                scope: String,
                signer: any CredentialSigner,
                session: URLSession = .shared
    ) {
        self.publishableKey = publishableKey
        self.scope = scope
        self.signer = signer
        self.session = session
        self.client = HttpClient(session: session)
    }

    public func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let endpoint = resolveEndpoint(path)
        let payload = String(data: body, encoding: .utf8) ?? ""

        let authHeader = try buildAuthHeader(
            endpoint: endpoint,
            scope: self.scope,
            signer: signer,
            payload: payload
        )

        var requestHeaders = [
            "Api-Key": publishableKey,
            "OMS-Wallet-Signature": authHeader
        ]
        for (name, value) in headers {
            requestHeaders[name] = value
        }

        let capture = Self.captureCurlIfNeeded(
            baseURL: baseURL,
            path: path,
            body: payload,
            headers: requestHeaders,
            statusCode: nil,
            responseBody: nil
        )
        let response = try await self.client.postJson(
            baseUrl: baseURL,
            path: path,
            body: payload,
            headers: requestHeaders
        )
        if let capture {
            Self.updateCurlCapture(
                capture,
                baseURL: baseURL,
                path: path,
                body: payload,
                headers: requestHeaders,
                statusCode: response.statusCode,
                responseBody: response.body
            )
        }

        return WebRPCHTTPResponse(
            statusCode: response.statusCode,
            body: response.body
        )
    }

    private func buildAuthHeader(endpoint: String, scope: String, signer: any CredentialSigner, payload: String) throws -> String {
        let nonce = try signer.nextNonce()
        let preimage = RequestUtils.buildWalletRequestPreimage(endpoint: endpoint, nonce: nonce, scope: scope, payload: payload)
        let signature = try signer.sign(preimage: preimage)

        return try RequestUtils.buildWalletSignatureHeader(
            alg: signer.alg,
            scope: scope,
            cred: signer.credentialId(),
            nonce: nonce,
            sig: signature
        )
    }

    private func resolveEndpoint(_ path: String) -> String {
        if path.hasPrefix(WaasAPI.basePath) {
            return String(path.dropFirst(WaasAPI.basePath.count))
        }
        if path.hasPrefix("/") {
            return path
        }
        return "/\(path)"
    }

    private static func captureCurlIfNeeded(
        baseURL: String,
        path: String,
        body: String,
        headers: [String: String],
        statusCode: Int?,
        responseBody: Data?
    ) -> URL? {
        guard shouldCaptureCurl(path: path),
              let directory = curlCaptureDirectory() else {
            return nil
        }
        let captureURL = directory.appendingPathComponent(curlCaptureFilename(path: path))
        writeCurlCapture(
            captureURL,
            baseURL: baseURL,
            path: path,
            body: body,
            headers: headers,
            statusCode: statusCode,
            responseBody: responseBody
        )
        updateLatestCurl(captureURL, in: directory, statusCode: statusCode)
        return captureURL
    }

    private static func updateCurlCapture(
        _ captureURL: URL,
        baseURL: String,
        path: String,
        body: String,
        headers: [String: String],
        statusCode: Int,
        responseBody: Data
    ) {
        writeCurlCapture(
            captureURL,
            baseURL: baseURL,
            path: path,
            body: body,
            headers: headers,
            statusCode: statusCode,
            responseBody: responseBody
        )
        guard let directory = curlCaptureDirectory() else { return }
        updateLatestCurl(captureURL, in: directory, statusCode: statusCode)
    }

    private static func writeCurlCapture(
        _ captureURL: URL,
        baseURL: String,
        path: String,
        body: String,
        headers: [String: String],
        statusCode: Int?,
        responseBody: Data?
    ) {
        let responseURL = captureURL.deletingPathExtension().appendingPathExtension("response.txt")
        if let responseBody {
            try? responseBody.write(to: responseURL)
        }

        var lines: [String] = [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "# Captured: \(ISO8601DateFormatter().string(from: Date()))",
            "# WebRPC path: \(path)"
        ]
        if let statusCode {
            lines.append("# Response status: \(statusCode)")
            lines.append("# Response body: \(responseURL.path)")
        } else {
            lines.append("# Response status: pending")
        }
        lines.append("")
        lines.append("curl -i -sS -X POST \(shellSingleQuote(joinURL(baseURL: baseURL, path: path))) \\")
        lines.append("  -H \(shellSingleQuote("Content-Type: application/json")) \\")
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            lines.append("  -H \(shellSingleQuote("\(name): \(value)")) \\")
        }
        lines.append("  --data-binary @- <<'JSON'")
        lines.append(body)
        lines.append("JSON")
        lines.append("")
        try? Data(lines.joined(separator: "\n").utf8).write(to: captureURL)
    }

    private static func updateLatestCurl(_ captureURL: URL, in directory: URL, statusCode: Int?) {
        copyCapture(captureURL, to: directory.appendingPathComponent("waas-latest-curl.sh"))
        guard let statusCode, statusCode >= 400 else { return }
        copyCapture(captureURL, to: directory.appendingPathComponent("waas-latest-failed-curl.sh"))
        let responseURL = captureURL.deletingPathExtension().appendingPathExtension("response.txt")
        guard FileManager.default.fileExists(atPath: responseURL.path) else { return }
        copyCapture(responseURL, to: directory.appendingPathComponent("waas-latest-failed-response.txt"))
    }

    private static func copyCapture(_ source: URL, to destination: URL) {
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
    }

    private static func shouldCaptureCurl(path: String) -> Bool {
        path.hasSuffix("/PrepareEthereumTransaction") || path.hasSuffix("/Execute")
    }

    private static func curlCaptureDirectory() -> URL? {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseURL.appendingPathComponent("waas-curl-captures", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    private static func curlCaptureFilename(path: String) -> String {
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let route = path
            .split(separator: "/")
            .joined(separator: "-")
        return "waas-\(timestamp)-\(route).sh"
    }

    private static func joinURL(baseURL: String, path: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
