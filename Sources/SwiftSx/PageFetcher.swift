import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches the raw body of a web page through the sandbox-gated HTTP transport,
/// with browser-like headers to reduce trivial anti-bot blocking.
///
/// This is the shared primitive behind the `--html` (raw) and `--text`
/// (extracted) output modes: each result URL is fetched the same way, and every
/// fetch is gated through the ShellKit sandbox by ``HTTPTransport``.
public struct PageFetcher: Sendable {

    // MARK: - State

    let transport: HTTPTransport

    // MARK: - Init

    public init(transport: HTTPTransport = HTTPTransport()) {
        self.transport = transport
    }

    /// Build a fetcher whose transport applies `timeout` (seconds) per request.
    public init(timeout: TimeInterval) {
        self.transport = HTTPTransport(timeout: timeout)
    }

    /// A desktop-browser `User-Agent`, sent so pages that block obvious bots
    /// still return content.
    public static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    // MARK: - Request building

    /// Builds the GET request used to fetch `urlString`, with browser-like
    /// headers.
    ///
    /// - Throws: ``SxError`` with code `.usage` when `urlString` is not a valid
    ///   absolute `http`/`https` URL.
    func makeRequest(_ urlString: String) throws -> HTTPRequest {
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw SxError(.usage, "cannot fetch '\(urlString)': not a valid absolute http(s) URL")
        }

        var request = HTTPRequest(method: .get, url: url)
        request.headerFields[.userAgent] = Self.browserUserAgent
        request.headerFields[.accept] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        request.headerFields[.acceptLanguage] = "en-US,en;q=0.9"
        return request
    }

    // MARK: - Fetch

    /// Fetches the raw body at `urlString`.
    ///
    /// - Returns: The response body decoded as UTF-8 (lossily — web pages are
    ///   overwhelmingly UTF-8, and a simplified port does not sniff charsets).
    /// - Throws:
    ///   - ``SxError`` with code `.usage` for an invalid URL.
    ///   - ``SxError`` with code `.refused` when the sandbox denies the URL.
    ///   - ``SxError`` with code `.general` for a non-2xx status or a transport
    ///     failure.
    ///   - `CancellationError` if the task is cancelled.
    public func fetch(_ urlString: String) async throws -> String {
        let request = try makeRequest(urlString)

        let data: Data
        let response: HTTPResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let sxError as SxError {
            throw sxError                // sandbox refusal (exit 3) passes through
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SxError(.general, "could not fetch \(urlString): \(error)")
        }

        guard (200..<300).contains(response.status.code) else {
            throw SxError(.general, "fetch of \(urlString) returned HTTP \(response.status.code)")
        }

        return String(decoding: data, as: UTF8.self)
    }
}
