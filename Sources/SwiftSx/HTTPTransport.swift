import Foundation
import HTTPTypes
import HTTPTypesFoundation
import ShellKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A thin, Sendable wrapper around `URLSession` that gates every outbound
/// request through the ShellKit sandbox before sending it.
///
/// Inject a custom `URLSession` (e.g. one backed by `MockURLProtocol`) to
/// replace real network I/O in unit tests, or use `init(timeout:)` to apply a
/// per-request timeout from configuration.
public struct HTTPTransport: Sendable {

    // MARK: - State

    let session: URLSession

    // MARK: - Init

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Build a transport whose session applies `timeout` (seconds) to each
    /// request and resource, so configured failover latency is honored.
    public init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Send

    /// Authorize the URL through the sandbox, then perform the request.
    ///
    /// - Parameters:
    ///   - request: The HTTP request to send.
    ///   - body: An optional request body. When non-nil the request is sent via
    ///     `URLSession.upload(for:from:)`; otherwise via `URLSession.data(for:)`.
    /// - Returns: The raw response body and the typed `HTTPResponse`.
    /// - Throws:
    ///   - `BackendError(.network, …)` when `request` has no URL.
    ///   - `SxError(.refused, …)` when the sandbox denies the URL (exit 3).
    ///   - `CancellationError` if the task is cancelled during authorization.
    ///   - Any `URLSession` transport error.
    public func send(_ request: HTTPRequest, body: Data? = nil) async throws -> (Data, HTTPResponse) {
        guard let url = request.url else {
            throw BackendError(
                backend: "http",
                code: .network,
                message: "request has no URL"
            )
        }
        do {
            try await Shell.authorize(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A sandbox/policy denial is distinct from a network failure: surface
            // it as a stable "refused" (exit 3) so an agent can tell them apart.
            throw SxError(.refused, "request to \(url.host ?? url.absoluteString) was refused by the sandbox: \(error)")
        }
        if let body {
            return try await session.upload(for: request, from: body)
        }
        return try await session.data(for: request)
    }
}
