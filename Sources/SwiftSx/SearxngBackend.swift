import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - SearxngResponse (private wire type)

/// The JSON envelope returned by SearXNG's `/search` endpoint.
private struct SearxngResponse: Decodable {
    let results: [SearchResult]
}

// MARK: - SearxngBackend

/// A single-instance SearXNG search backend.
///
/// Build one directly when you have a single configured instance, or use
/// ``MultiSearxngBackend`` (and its factory ``SearxngBackend/makeBackend(from:transport:)``)
/// when the config may supply multiple instance URLs.
public struct SearxngBackend: SearchBackend {

    // MARK: - Properties

    /// The SearXNG instance base URL (e.g. `"https://searx.example.com"`).
    public let baseURL: String
    /// The HTTP method to use: `"GET"` or `"POST"` (always uppercased at init).
    public let httpMethod: String
    /// HTTP Basic-auth username, or empty string when not required.
    public let username: String
    /// HTTP Basic-auth password, or empty string when not required.
    public let password: String
    /// When `true`, omit the `User-Agent` header from requests.
    public let noUserAgent: Bool
    /// The transport layer (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    public init(
        baseURL: String,
        httpMethod: String = "GET",
        username: String = "",
        password: String = "",
        noUserAgent: Bool = false,
        transport: HTTPTransport = HTTPTransport()
    ) {
        self.baseURL     = baseURL
        self.httpMethod  = httpMethod.uppercased()
        self.username    = username
        self.password    = password
        self.noUserAgent = noUserAgent
        self.transport   = transport
    }

    // MARK: - SearchBackend

    public var name: String { "searxng" }

    /// `true` when `baseURL` is non-empty and parses as an absolute URL with
    /// both a non-empty scheme and a non-empty host.
    public var isAvailable: Bool {
        guard !baseURL.isEmpty,
              let components = URLComponents(string: baseURL),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    /// Perform a search against this SearXNG instance.
    ///
    /// - Throws: `BackendError(.unavailable, …)` when `isAvailable` is `false`.
    /// - Throws: `BackendError` with an appropriate code on any HTTP or decode failure.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        guard isAvailable else {
            throw BackendError(
                backend: "searxng",
                code: .unavailable,
                message: "searxng is not configured — set searxng_url in config.toml"
            )
        }

        let (request, body) = try makeRequest(options)

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(request, body: body)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx          // e.g. a sandbox refusal — propagate as-is (exit 3)
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "searxng",
                code: .network,
                message: "searxng request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(SearxngResponse.self, from: data)
                // Honor the requested maximum (SearXNG may return a full page).
                if options.numResults > 0, decoded.results.count > options.numResults {
                    return Array(decoded.results.prefix(options.numResults))
                }
                return decoded.results
            } catch {
                throw BackendError(
                    backend: "searxng",
                    code: .invalidResponse,
                    message: "searxng returned a response that could not be parsed"
                )
            }
        case 401, 403:
            throw BackendError(
                backend: "searxng",
                code: .auth,
                message: "searxng rejected the request (HTTP \(status)) — check searxng_username/searxng_password"
            )
        case 429:
            throw BackendError(
                backend: "searxng",
                code: .rateLimit,
                message: "searxng is rate limiting (HTTP 429) — back off and retry"
            )
        default:
            throw BackendError(
                backend: "searxng",
                code: .network,
                message: "searxng returned HTTP \(status)"
            )
        }
    }

    // MARK: - Request construction (internal for testability)

    /// Build the `HTTPRequest` (and optional body data) for the given options.
    ///
    /// This is factored out of `search(_:)` so tests can assert URL, method,
    /// headers, and body without touching the network.
    ///
    /// - Throws: `BackendError(.network, …)` when the endpoint URL cannot be built.
    func makeRequest(_ options: SearchOptions) throws -> (HTTPRequest, Data?) {
        // Trim a trailing slash from baseURL before appending the path.
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpointString = "\(base)/search"

        // Build the query/form parameters (deterministic ordering where possible).
        var params: [(String, String)] = []

        // q — prefix site: when options.site is non-empty.
        let queryString: String
        if options.site.isEmpty {
            queryString = options.query
        } else {
            queryString = "site:\(options.site) \(options.query)"
        }
        params.append(("q", queryString))

        // format is always json.
        params.append(("format", "json"))

        // categories — only when non-empty.
        if !options.categories.isEmpty {
            params.append(("categories", options.categories.joined(separator: ",")))
        }

        // engines — only when non-empty.
        if !options.engines.isEmpty {
            params.append(("engines", options.engines.joined(separator: ",")))
        }

        // language — only when non-empty.
        if !options.language.isEmpty {
            params.append(("language", options.language))
        }

        // safesearch — only when non-empty; map the three documented levels.
        if !options.safeSearch.isEmpty {
            let mapped: String
            switch options.safeSearch {
            case "none", "off": mapped = "0"
            case "moderate":    mapped = "1"
            case "strict":      mapped = "2"
            default:         mapped = options.safeSearch
            }
            params.append(("safesearch", mapped))
        }

        // time_range — only when non-empty.
        if !options.timeRange.isEmpty {
            params.append(("time_range", options.timeRange))
        }

        // pageno — only when > 1.
        if options.pageNo > 1 {
            params.append(("pageno", String(options.pageNo)))
        }

        // Build the request depending on HTTP method.
        let isPost = httpMethod == "POST"

        let url: URL
        var bodyData: Data? = nil

        if isPost {
            // POST: params go in the body as application/x-www-form-urlencoded.
            guard let endpointURL = URL(string: endpointString) else {
                throw BackendError(
                    backend: "searxng",
                    code: .network,
                    message: "searxng request failed: could not build endpoint URL from '\(endpointString)'"
                )
            }
            url = endpointURL
            bodyData = formURLEncode(params).data(using: .utf8)
        } else {
            // GET: params go in the query string.
            guard var components = URLComponents(string: endpointString) else {
                throw BackendError(
                    backend: "searxng",
                    code: .network,
                    message: "searxng request failed: could not build endpoint URL from '\(endpointString)'"
                )
            }
            components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
            guard let builtURL = components.url else {
                throw BackendError(
                    backend: "searxng",
                    code: .network,
                    message: "searxng request failed: could not build endpoint URL from '\(endpointString)'"
                )
            }
            url = builtURL
        }

        let method: HTTPRequest.Method = isPost ? .post : .get
        var request = HTTPRequest(method: method, url: url)

        // Standard headers.
        request.headerFields[.accept] = "application/json"
        request.headerFields[.acceptEncoding] = "gzip, deflate"

        if !noUserAgent {
            request.headerFields[.userAgent] = "sx/2.0"
        }

        if isPost {
            request.headerFields[.contentType] = "application/x-www-form-urlencoded"
        }

        // Basic auth — only when both username and password are non-empty.
        if !username.isEmpty && !password.isEmpty {
            let credentials = "\(username):\(password)"
            if let credData = credentials.data(using: .utf8) {
                request.headerFields[.authorization] = "Basic \(credData.base64EncodedString())"
            }
        }

        return (request, bodyData)
    }

    // MARK: - Private helpers

    /// Percent-encode a list of key/value pairs as `application/x-www-form-urlencoded`.
    private func formURLEncode(_ params: [(String, String)]) -> String {
        params.map { key, value in
            let encodedKey   = urlFormEncode(key)
            let encodedValue = urlFormEncode(value)
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    /// Encode a single string component using form-URL encoding rules
    /// (spaces → `+`, reserved chars percent-encoded).
    private func urlFormEncode(_ string: String) -> String {
        // RFC 3986 unreserved characters, minus the space which becomes '+'.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let percentEncoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        // Per application/x-www-form-urlencoded, spaces become '+' (already
        // percent-encoded above as %20 by alphanumerics exclusion; convert).
        return percentEncoded.replacingOccurrences(of: "%20", with: "+")
    }
}

// MARK: - HTTPField.Name extensions for SearXNG

private extension HTTPField.Name {
    static let acceptEncoding = HTTPField.Name("Accept-Encoding")!
}

// MARK: - Factory (builds a SearchBackend from Config)

extension SearxngBackend {
    /// Build the canonical SearXNG backend from a loaded `Config`.
    ///
    /// When `config.searxngURLs` is non-empty it wins; otherwise falls back to
    /// the single `config.searxngURL`. The result is always a
    /// ``MultiSearxngBackend`` (even for one URL) so the caller doesn't need to
    /// branch.
    ///
    /// - Parameters:
    ///   - config: The loaded and normalised configuration.
    ///   - transport: The HTTP transport to inject (default: `.shared` session).
    /// - Returns: A ``MultiSearxngBackend`` wrapping one or more ``SearxngBackend`` instances.
    public static func makeBackend(
        from config: Config,
        transport: HTTPTransport? = nil
    ) -> any SearchBackend {
        // Apply the configured request timeout (and TLS-verification override for
        // a self-hosted instance) unless a transport is injected — tests inject a
        // mock-backed session. `no_verify_ssl` is honored on Apple platforms only
        // (see HTTPTransport); it's scoped to SearXNG because the public API
        // backends always use valid certificates.
        let resolvedTransport = transport
            ?? HTTPTransport(timeout: config.timeout, allowInsecureTLS: config.noVerifySSL)

        // Prefer the deduped/normalised list; fall back to the single URL.
        let urls: [String] = config.searxngURLs.isEmpty
            ? (config.searxngURL.isEmpty ? [] : [config.searxngURL])
            : config.searxngURLs

        let instances = urls.map { url in
            SearxngBackend(
                baseURL: url,
                httpMethod: config.httpMethod,
                username: config.searxngUsername,
                password: config.searxngPassword,
                noUserAgent: config.noUserAgent,
                transport: resolvedTransport
            )
        }

        return MultiSearxngBackend(
            instances: instances,
            strategy: config.searxngStrategy
        )
    }
}
