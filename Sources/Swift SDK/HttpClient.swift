import Foundation

struct HttpResponse {
    let statusCode: Int
    let body: Data
    let headers: [String: String]
}

enum HttpError: Error {
    case invalidUrl(String)
    case invalidResponse
    case encodingFailed
    case transport(Error)
}

@available(macOS 12.0, iOS 15.0, *)
final class HttpClient : Sendable {
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30
    ) {
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    func postJson(
        baseUrl: String,
        path: String,
        body: String,
        headers: [String: String] = [:]
    ) async throws -> HttpResponse {
        let urlString = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: urlString) else {
            throw HttpError.invalidUrl(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        guard let bodyData = body.data(using: .utf8) else {
            throw HttpError.encodingFailed
        }
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HttpError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HttpError.invalidResponse
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                responseHeaders[keyString] = valueString
            }
        }

        return HttpResponse(
            statusCode: httpResponse.statusCode,
            body: data,
            headers: responseHeaders
        )
    }
}
