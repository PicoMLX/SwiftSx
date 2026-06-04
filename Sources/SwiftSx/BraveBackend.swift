import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - BraveResponse (private wire type)

/// The JSON envelope returned by the Brave Search `/web/search` endpoint.
private struct BraveResponse: Decodable {
    let web: Web?

    struct Web: Decodable {
        let results: [Item]?
    }

    struct Item: Decodable {
        let title: String?
        let url: String?
        let description: String?
    }
}

// MARK: - BraveBackend

/// A Brave Search backend.
///
/// Requires a Brave Search API key supplied either via `BRAVE_API_KEY` (which
/// the config loader maps into ``BraveConfig/apiKey`` before reaching this
/// type) or via the `engines_brave.api_key` config key.
public struct BraveBackend: SearchBackend {

    // MARK: - Properties

    /// The Brave Search API key.
    public let apiKey: String
    /// The transport layer (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    public init(
        apiKey: String,
        transport: HTTPTransport = HTTPTransport()
    ) {
        self.apiKey    = apiKey
        self.transport = transport
    }

    // MARK: - SearchBackend

    public var name: String { "brave" }

    /// `true` when `apiKey` is non-empty.
    public var isAvailable: Bool { !apiKey.isEmpty }

    /// Perform a search against the Brave Search API.
    ///
    /// - Throws: `BackendError(.unavailable, …)` when `isAvailable` is `false`.
    /// - Throws: `BackendError` with an appropriate code on any HTTP or decode failure.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        guard isAvailable else {
            throw BackendError(
                backend: "brave",
                code: .unavailable,
                message: "brave is not configured — set BRAVE_API_KEY or engines_brave.api_key"
            )
        }

        let request = try makeRequest(options)

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(request, body: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx          // e.g. a sandbox refusal — propagate as-is (exit 3)
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "brave",
                code: .network,
                message: "brave request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(BraveResponse.self, from: data)
                return (decoded.web?.results ?? []).map { item in
                    SearchResult(
                        title:   item.title       ?? "",
                        url:     item.url         ?? "",
                        content: item.description ?? "",
                        engine:  "brave",
                        engines: ["brave"]
                    )
                }
            } catch {
                throw BackendError(
                    backend: "brave",
                    code: .invalidResponse,
                    message: "brave returned a response that could not be parsed"
                )
            }
        case 401, 403:
            throw BackendError(
                backend: "brave",
                code: .auth,
                message: "brave rejected the request (HTTP \(status)) — check the Brave API key (BRAVE_API_KEY)"
            )
        case 429:
            throw BackendError(
                backend: "brave",
                code: .rateLimit,
                message: "brave is rate limiting (HTTP 429) — back off and retry"
            )
        default:
            throw BackendError(
                backend: "brave",
                code: .network,
                message: "brave returned HTTP \(status)"
            )
        }
    }

    // MARK: - Request construction (internal for testability)

    /// Build the `HTTPRequest` for the given options.
    ///
    /// This is factored out of `search(_:)` so tests can assert URL, method,
    /// and headers without touching the network.
    ///
    /// - Throws: `BackendError(.network, …)` when the endpoint URL cannot be built.
    func makeRequest(_ options: SearchOptions) throws -> HTTPRequest {
        // q — prefix site: when options.site is non-empty.
        let queryString: String
        if options.site.isEmpty {
            queryString = options.query
        } else {
            queryString = "site:\(options.site) \(options.query)"
        }

        // count — clamp to 1...20; default to 10 when ≤ 0.
        let rawCount = options.numResults
        let count: Int
        if rawCount <= 0 {
            count = 10
        } else if rawCount > 20 {
            count = 20
        } else {
            count = rawCount
        }

        // safesearch — map the documented levels.
        // Both "none" and "off" map to Brave's "off"; "strict" → "strict";
        // everything else (including "moderate") → "moderate".
        let safeSearch: String
        switch options.safeSearch {
        case "none", "off": safeSearch = "off"
        case "strict":      safeSearch = "strict"
        default:            safeSearch = "moderate"
        }

        // Build query items.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q",          value: queryString),
            URLQueryItem(name: "count",      value: String(count)),
            URLQueryItem(name: "safesearch", value: safeSearch),
        ]

        // offset — zero-based page index; Brave's max is 9. Only send when pageNo > 1.
        // Brave's offset is a page index, not a result offset, so offset = pageNo - 1.
        if options.pageNo > 1 {
            let offset = min(options.pageNo - 1, 9)
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        // search_lang / ui_lang — Brave's search_lang wants a bare language code (e.g.
        // "en"), not a full locale ("en-US"). When the caller supplies a locale that
        // contains a "-", split on the first "-" and send the language code as
        // search_lang plus the original locale string as ui_lang.
        if !options.language.isEmpty {
            if let dashIndex = options.language.firstIndex(of: "-") {
                let langCode = String(options.language[options.language.startIndex..<dashIndex])
                queryItems.append(URLQueryItem(name: "search_lang", value: langCode))
                queryItems.append(URLQueryItem(name: "ui_lang",     value: options.language))
            } else {
                queryItems.append(URLQueryItem(name: "search_lang", value: options.language))
            }
        }

        // result_filter — map recognized categories to Brave's result_filter (comma-joined).
        // Recognized: "news" → "news", "videos" → "videos", "general"/"web" → "web".
        // Unrecognized categories are dropped; if nothing maps, omit result_filter entirely.
        if !options.categories.isEmpty {
            let mapped: [String] = options.categories.compactMap { cat in
                switch cat {
                case "news":           return "news"
                case "videos":         return "videos"
                case "general", "web": return "web"
                default:               return nil
                }
            }
            if !mapped.isEmpty {
                queryItems.append(URLQueryItem(name: "result_filter", value: mapped.joined(separator: ",")))
            }
        }

        // freshness — map options.timeRange to Brave's freshness values.
        // Accepted short forms: d/day→pd, w/week→pw, m/month→pm, y/year→py.
        // Unknown values are omitted (do not send a bad value).
        if !options.timeRange.isEmpty {
            let freshness: String?
            switch options.timeRange {
            case "d", "day":   freshness = "pd"
            case "w", "week":  freshness = "pw"
            case "m", "month": freshness = "pm"
            case "y", "year":  freshness = "py"
            default:           freshness = nil
            }
            if let freshness {
                queryItems.append(URLQueryItem(name: "freshness", value: freshness))
            }
        }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
            ?? URLComponents()
        components.queryItems = queryItems

        guard let url = components.url else {
            throw BackendError(
                backend: "brave",
                code: .network,
                message: "brave request failed: could not build endpoint URL"
            )
        }

        var request = HTTPRequest(method: .get, url: url)
        request.headerFields[.accept] = "application/json"
        request.headerFields[.xSubscriptionToken] = apiKey

        return request
    }
}

// MARK: - HTTPField.Name extensions for Brave

private extension HTTPField.Name {
    static let xSubscriptionToken = HTTPField.Name("X-Subscription-Token")!
}

// MARK: - Factory (builds a BraveBackend from Config)

extension BraveBackend {
    /// Build a ``BraveBackend`` from a loaded `Config`.
    ///
    /// - Parameters:
    ///   - config: The loaded and normalised configuration.
    ///   - transport: The HTTP transport to inject (default: shared session).
    /// - Returns: A ``BraveBackend`` configured from `config.enginesBrave`.
    public static func makeBrave(
        from config: Config,
        transport: HTTPTransport? = nil
    ) -> BraveBackend {
        BraveBackend(
            apiKey:    config.enginesBrave.apiKey,
            transport: transport ?? HTTPTransport(timeout: config.timeout)
        )
    }
}
