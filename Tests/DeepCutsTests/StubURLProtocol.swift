import Foundation

/// A `URLSession` that answers every request from a closure, so network code runs without a network.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)
    nonisolated(unsafe) static var handler: Handler?

    static func session(_ handler: @escaping Handler) -> URLSession {
        Self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer = Self.handler?(request) ?? (status: 500, body: Data())
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: answer.status, httpVersion: nil, headerFields: nil)
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
