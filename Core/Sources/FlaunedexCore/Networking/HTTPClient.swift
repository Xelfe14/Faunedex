import Foundation

/// Minimal async HTTP abstraction so services can be exercised with injected
/// fixtures in tests instead of live network calls.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Errors surfaced by the networking layer and the services on top of it.
public enum FlaunedexNetworkError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
    case missingAPIKey
    case decoding(String)
}

/// Production `HTTPClient` backed by `URLSession`, always sending the app's
/// descriptive User-Agent (required by Wikimedia/Wikidata/GBIF).
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(FlaunedexConfig.userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FlaunedexNetworkError.invalidResponse
        }
        return (data, http)
    }
}

public extension HTTPClient {
    /// Perform a GET, validate a 2xx status, and return the body.
    func getData(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FlaunedexNetworkError.badStatus(response.statusCode)
        }
        return data
    }
}
