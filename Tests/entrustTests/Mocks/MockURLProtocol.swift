import Foundation

/// A mock URL protocol for intercepting network requests in tests
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Handler type for mocking responses
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// The handler to use for all requests
    nonisolated(unsafe) static var requestHandler: RequestHandler?

    /// Recorded requests for verification
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.recordedRequests.append(request)

        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Reset the mock state
    static func reset() {
        requestHandler = nil
        recordedRequests = []
    }

    /// Create a mock session configured with this protocol
    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Response Builders

extension MockURLProtocol {
    /// Create a successful JSON response
    static func successResponse(
        for url: URL,
        json: [String: Any],
        statusCode: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }

    /// Create a successful JSON response with Codable
    static func successResponse<T: Encodable>(
        for url: URL,
        body: T,
        statusCode: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try JSONEncoder().encode(body)
        return (response, data)
    }

    /// Create an error response
    static func errorResponse(
        for url: URL,
        statusCode: Int,
        message: String = "Error"
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = message.data(using: .utf8)!
        return (response, data)
    }
}
