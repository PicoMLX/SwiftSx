import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - TavilyRequest (private wire type)

/// The JSON body sent to the Tavily `/search` endpoint.
private struct TavilyRequest: Encodable {
    let query: String
    let searchDepth: String
    let maxResults: Int
    let includeRawContent: Bool
    let includeAnswer: Bool
    /// Optional domain filter; when non-nil, sent as `include_domains` JSON array.
    let includeDomains: [String]?
    /// Optional time range filter (`day`, `week`, `month`, `year`).
    let timeRange: String?
    /// Optional topic / category filter (`news`, `finance`; omit for `general`).
    let topic: String?

    enum CodingKeys: String, CodingKey {
        case query             = "query"
        case searchDepth       = "search_depth"
        case maxResults        = "max_results"
        case includeRawContent = "include_raw_content"
        case includeAnswer     = "include_answer"
        case includeDomains    = "include_domains"
        case timeRange         = "time_range"
        case topic             = "topic"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query,             forKey: .query)
        try container.encode(searchDepth,       forKey: .searchDepth)
        try container.encode(maxResults,        forKey: .maxResults)
        try container.encode(includeRawContent, forKey: .includeRawContent)
        try container.encode(includeAnswer,     forKey: .includeAnswer)
        try container.encodeIfPresent(includeDomains, forKey: .includeDomains)
        try container.encodeIfPresent(timeRange,      forKey: .timeRange)
        try container.encodeIfPresent(topic,          forKey: .topic)
    }
}

// MARK: - TavilyResponse (private wire type)

/// The JSON envelope returned by the Tavily `/search` endpoint.
private struct TavilyResponse: Decodable {
    let results: [Item]?
    /// Tavily's AI-generated answer (present when `include_answer` was requested).
    let answer: String?

    struct Item: Decodable {
        let title: String?
        let url: String?
        let content: String?
        let rawContent: String?
        let score: Double?

        enum CodingKeys: String, CodingKey {
            case title      = "title"
            case url        = "url"
            case content    = "content"
            case rawContent = "raw_content"
            case score      = "score"
        }
    }
}

// MARK: - TavilyBackend

/// A Tavily Search backend.
///
/// Requires a Tavily API key supplied either via `TAVILY_API_KEY` (which the
/// config loader maps into ``TavilyConfig/apiKey`` before reaching this type)
/// or via the `engines_tavily.api_key` config key.
public struct TavilyBackend: SearchBackend {

    // MARK: - Properties

    /// The Tavily API key.
    public let apiKey: String
    /// Search depth: `"basic"` or `"advanced"`.
    public let searchDepth: String
    /// Whether to include raw page content in results.
    public let includeRawContent: Bool
    /// Whether to include an AI-generated answer in results.
    public let includeAnswer: Bool
    /// The transport layer (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    public init(
        apiKey: String,
        searchDepth: String = "basic",
        includeRawContent: Bool = false,
        includeAnswer: Bool = false,
        transport: HTTPTransport = HTTPTransport()
    ) {
        self.apiKey            = apiKey
        self.searchDepth       = searchDepth
        self.includeRawContent = includeRawContent
        self.includeAnswer     = includeAnswer
        self.transport         = transport
    }

    // MARK: - SearchBackend

    public var name: String { "tavily" }

    /// `true` when `apiKey` is non-empty.
    public var isAvailable: Bool { !apiKey.isEmpty }

    /// Perform a search against the Tavily Search API.
    ///
    /// - Throws: `BackendError(.unavailable, …)` when `isAvailable` is `false`.
    /// - Throws: `BackendError` with an appropriate code on any HTTP or decode failure.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        guard isAvailable else {
            throw BackendError(
                backend: "tavily",
                code: .unavailable,
                message: "tavily is not configured — set TAVILY_API_KEY or engines_tavily.api_key"
            )
        }

        // Tavily has no pagination — every result comes back on page 1. Throwing
        // (rather than returning []) lets the manager fall back to another engine
        // and gives an explicit search an actionable message instead of a silent
        // empty success.
        if options.pageNo > 1 {
            throw BackendError(
                backend: "tavily",
                code: .invalidResponse,
                message: "tavily does not support pagination — only page 1 is available (pageNo \(options.pageNo) requested)"
            )
        }

        let (request, bodyData) = try makeRequest(options)

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(request, body: bodyData)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx          // e.g. a sandbox refusal — propagate as-is (exit 3)
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "tavily",
                code: .network,
                message: "tavily request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(TavilyResponse.self, from: data)
                var results: [SearchResult] = (decoded.results ?? []).map { item in
                    let resolvedContent: String
                    if includeRawContent, let raw = item.rawContent, !raw.isEmpty {
                        resolvedContent = raw
                    } else {
                        resolvedContent = item.content ?? ""
                    }
                    return SearchResult(
                        title:   item.title ?? "",
                        url:     item.url   ?? "",
                        content: resolvedContent,
                        engine:  "tavily",
                        engines: ["tavily"]
                    )
                }
                // Surface Tavily's AI-generated answer (when requested and present)
                // as a leading result with category "answer" and no URL. Agents
                // reading --json can pick it out by category; --links (which skips
                // empty-URL entries) ignores it.
                if includeAnswer,
                   let answer = decoded.answer,
                   !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.insert(
                        SearchResult(
                            title:   "Tavily answer",
                            url:     "",
                            content: answer,
                            engine:  "tavily",
                            engines: ["tavily"],
                            category: "answer"
                        ),
                        at: 0
                    )
                }
                return results
            } catch {
                throw BackendError(
                    backend: "tavily",
                    code: .invalidResponse,
                    message: "tavily returned a response that could not be parsed"
                )
            }
        case 400:
            // A malformed request (bad query/options) is a usage problem: map to
            // .usage (exit 2) so an agent fixes the command rather than retrying
            // or escalating to fail-closed (exit 7).
            throw BackendError(
                backend: "tavily",
                code: .usage,
                message: "tavily rejected the request (HTTP 400) — check the query and options"
            )
        case 401, 403:
            throw BackendError(
                backend: "tavily",
                code: .auth,
                message: "tavily rejected the request (HTTP \(status)) — check the Tavily API key (TAVILY_API_KEY)"
            )
        case 429:
            throw BackendError(
                backend: "tavily",
                code: .rateLimit,
                message: "tavily is rate limiting (HTTP 429) — back off and retry"
            )
        case 432, 433:
            // Tavily plan / credit exhaustion — retrying the same command won't
            // help until the plan or credits are fixed, so this is fail-closed
            // (exit 7), not a transient rate-limit. Reuses .auth (→ exit 7).
            throw BackendError(
                backend: "tavily",
                code: .auth,
                message: "tavily usage limit reached (HTTP \(status)) — check your Tavily plan or credits"
            )
        default:
            throw BackendError(
                backend: "tavily",
                code: .network,
                message: "tavily returned HTTP \(status)"
            )
        }
    }

    // MARK: - Request construction (internal for testability)

    /// Build the `HTTPRequest` and JSON body `Data` for the given options.
    ///
    /// This is factored out of `search(_:)` so tests can assert URL, method,
    /// headers, and body without touching the network.
    ///
    /// - Throws: `BackendError(.network, …)` when the endpoint URL cannot be built
    ///   or the body cannot be encoded.
    func makeRequest(_ options: SearchOptions) throws -> (HTTPRequest, Data) {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw BackendError(
                backend: "tavily",
                code: .network,
                message: "tavily request failed: could not build endpoint URL"
            )
        }

        // query — plain query; site filtering is done via include_domains, not query prefix.
        let queryString = options.query

        // include_domains — when options.site is non-empty, restrict to that domain.
        let includeDomains: [String]? = options.site.isEmpty ? nil : [options.site]

        // max_results — clamp to 1...20; default to 10 when ≤ 0 (matches Brave).
        let maxResults: Int
        if options.numResults <= 0 {
            maxResults = 10
        } else if options.numResults > 20 {
            maxResults = 20
        } else {
            maxResults = options.numResults
        }

        // time_range — expand short forms to Tavily's accepted values.
        let timeRange: String?
        if options.timeRange.isEmpty {
            timeRange = nil
        } else {
            switch options.timeRange {
            case "d":           timeRange = "day"
            case "w":           timeRange = "week"
            case "m":           timeRange = "month"
            case "y":           timeRange = "year"
            default:            timeRange = options.timeRange
            }
        }

        // topic — map categories to Tavily's topic field.
        // "news" and "finance" are the two non-default topics; omit for "general".
        let topic: String?
        if options.categories.contains("news") {
            topic = "news"
        } else if options.categories.contains("finance") {
            topic = "finance"
        } else {
            topic = nil
        }

        let requestBody = TavilyRequest(
            query:             queryString,
            searchDepth:       searchDepth,
            maxResults:        maxResults,
            includeRawContent: includeRawContent,
            includeAnswer:     includeAnswer,
            includeDomains:    includeDomains,
            timeRange:         timeRange,
            topic:             topic
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(requestBody)
        } catch {
            throw BackendError(
                backend: "tavily",
                code: .network,
                message: "tavily request failed: could not encode request body: \(error)"
            )
        }

        var request = HTTPRequest(method: .post, url: url)
        request.headerFields[.contentType] = "application/json"
        request.headerFields[.authorization] = "Bearer \(apiKey)"

        return (request, bodyData)
    }
}

// MARK: - Factory (builds a TavilyBackend from Config)

extension TavilyBackend {
    /// Build a ``TavilyBackend`` from a loaded `Config`.
    ///
    /// - Parameters:
    ///   - config: The loaded and normalised configuration.
    ///   - transport: The HTTP transport to inject (default: shared session).
    /// - Returns: A ``TavilyBackend`` configured from `config.enginesTavily`.
    public static func makeTavily(
        from config: Config,
        transport: HTTPTransport? = nil
    ) -> TavilyBackend {
        TavilyBackend(
            apiKey:            config.enginesTavily.apiKey,
            searchDepth:       config.enginesTavily.searchDepth,
            includeRawContent: config.enginesTavily.includeRawContent,
            includeAnswer:     config.enginesTavily.includeAnswer,
            transport:         transport ?? HTTPTransport(timeout: config.timeout)
        )
    }
}
