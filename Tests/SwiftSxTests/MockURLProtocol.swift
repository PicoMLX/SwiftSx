import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - TestLockedBox

/// A simple Sendable wrapper around a value protected by an `NSLock`.
///
/// Used by `MockURLProtocol` to store the handler safely across concurrent
/// test tasks without requiring an actor.
final class TestLockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) { _value = value }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

// MARK: - MockURLProtocol

/// A `URLProtocol` subclass that intercepts every request and dispatches it
/// to a process-global handler closure.
///
/// Usage:
/// ```swift
/// let session = MockURLProtocol.session()
/// MockURLProtocol.handler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)!
///     return (response, Data("{\"results\":[]}".utf8))
/// }
/// ```
///
/// **Important**: `MockURLProtocol.handler` is process-global. Any test suite
/// that mutates it must be annotated `@Suite(.serialized)` to prevent races.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let state = TestLockedBox<Handler?>(nil)

    /// Set this before each test that needs mocked responses.
    static var handler: Handler? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "MockURLProtocol",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "no handler set"]
                )
            )
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

        // MARK: - Sequential responses helper

    /// Serve the given responses in order on successive requests; the last entry
    /// repeats once the list is exhausted. Thread-safe (the index is lock-guarded),
    /// so the `@Sendable` handler captures no mutable state.
    ///
    /// Each tuple supplies an HTTP `status` code and a raw `body` `Data` value.
    /// The installed handler builds a plain `application/json` `HTTPURLResponse`
    /// for every request, mirroring the convention used throughout the test suite.
    static func setSequentialResponses(_ responses: [(status: Int, body: Data)]) {
        struct State {
            var responses: [(status: Int, body: Data)]
            var index: Int = 0
        }
        let box = TestLockedBox(State(responses: responses))
        handler = { request in
            let (status, body) = box.withLock { state -> (Int, Data) in
                let i = min(state.index, state.responses.count - 1)
                state.index += 1
                return (state.responses[i].status, state.responses[i].body)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
    }

    // MARK: - Factory

    /// Create a `URLSession` whose requests are all handled by `MockURLProtocol`.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
