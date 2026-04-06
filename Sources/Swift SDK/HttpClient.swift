import Foundation;

public class HttpClient {
    
    private let baseURL: String
    
    public init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    @available(macOS 12.0, *)
    public func SendPostRequest(endpoint: String, payload: String, authorizationHeader: String?, accessKey: String?) async throws -> String {
        // Build the full URL
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw SDKError.invalidURL
        }
        
        // Set up the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.data(using: .utf8)
        
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        if let ak = accessKey {
            request.setValue(ak, forHTTPHeaderField: "X-Access-Key")
        }
        
        // Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check the HTTP status code
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SDKError.requestFailed
        }
        
        // Return the response as a String
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// Custom errors for your SDK
public enum SDKError: Error {
    case invalidURL
    case requestFailed
}
