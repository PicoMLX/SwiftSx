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

// MARK: - UncheckedSendableBox

/// Wraps a value so it can cross an isolation boundary (e.g. be captured by a
/// `Task`) regardless of whether the value's own type is `Sendable`.
///
/// `URLProtocol` is not `Sendable` on Apple platforms and carries an
/// *unavailable* `Sendable` conformance on swift-corelibs-foundation (Linux),
/// so a `URLProtocol` subclass instance can't be captured directly by the
/// dispatching `Task` in ``MockURLProtocol/startLoading()``. Routing it through
/// this box compiles on both — see that method.
struct UncheckedSendableBox<Wrapped>: @unchecked Sendable {
    let value: Wrapped
    init(_ value: Wrapped) { self.value = value }
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
        // Capture the handler and request *synchronously*, then deliver the
        // response on a detached `Task`, off the URLSession work queue.
        //
        // Capturing the handler here (rather than reading the process-global
        // inside the Task) preserves the original timing: the handler in effect
        // when the request starts is the one that serves it, even if another
        // serialized suite swaps `handler` before the Task is scheduled.
        //
        // The dispatch itself matters because a handler may read the request body
        // (e.g. to echo a JSON-RPC id). On swift-corelibs-foundation (Linux),
        // reading `httpBodyStream` *synchronously* on the work queue that also
        // feeds the stream can deadlock when the body isn't yet fully buffered —
        // an intermittent hang. Reading the handler (a lock-guarded property) is
        // safe on the queue; only the body read must move off it. Dispatching
        // matches the official MCP SDK's own `URLProtocol` mock (run on Linux CI).
        //
        // `URLProtocol` isn't `Sendable` (and is *unavailably* `Sendable` on
        // Linux), so the instance is routed through an `UncheckedSendableBox` to
        // be captured by the `Task` under this package's Swift 6 mode.
        let handler = MockURLProtocol.handler
        let request = self.request
        let box = UncheckedSendableBox(self)
        Task {
            let `protocol` = box.value
            let client = `protocol`.client
            guard let handler else {
                client?.urlProtocol(
                    `protocol`,
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
                client?.urlProtocol(`protocol`, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(`protocol`, didLoad: data)
                client?.urlProtocolDidFinishLoading(`protocol`)
            } catch {
                client?.urlProtocol(`protocol`, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}

    // MARK: - Factory

    /// Create a `URLSession` whose requests are all handled by `MockURLProtocol`.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
