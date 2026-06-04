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
/// replace real network I/O in unit tests.
public struct HTTPTransport: Sendable {

    // MARK: - State

    let session: URLSession

    // MARK: - Init

    public init(session: URLSession = .shared) {
        self.session = session
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
    ///   - Any sandbox error raised by `Shell.authorize`.
    ///   - Any `URLSession` transport error.
    public func send(_ request: HTTPRequest, body: Data? = nil) async throws -> (Data, HTTPResponse) {
        guard let url = request.url else {
            throw BackendError(
                backend: "http",
                code: .invalidResponse,
                message: "request has no URL"
            )
        }
        try await Shell.authorize(url)
        if let body {
            return try await session.upload(for: request, from: body)
        }
        return try await session.data(for: request)
    }
}
