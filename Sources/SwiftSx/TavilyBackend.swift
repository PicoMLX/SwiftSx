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

    enum CodingKeys: String, CodingKey {
        case query            = "query"
        case searchDepth      = "search_depth"
        case maxResults       = "max_results"
        case includeRawContent = "include_raw_content"
        case includeAnswer    = "include_answer"
    }
}

// MARK: - TavilyResponse (private wire type)

/// The JSON envelope returned by the Tavily `/search` endpoint.
private struct TavilyResponse: Decodable {
    let results: [Item]

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

        let (request, bodyData) = try makeRequest(options)

        let (data, response): (Data, HTTPResponse)
        do {
            (data, response) = try await transport.send(request, body: bodyData)
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
                return decoded.results.map { item in
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
            } catch {
                throw BackendError(
                    backend: "tavily",
                    code: .invalidResponse,
                    message: "tavily returned a response that could not be parsed"
                )
            }
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

        // q — prefix site: when options.site is non-empty.
        let queryString: String
        if options.site.isEmpty {
            queryString = options.query
        } else {
            queryString = "site:\(options.site) \(options.query)"
        }

        // max_results — default to 10 when ≤ 0 or > 20.
        let maxResults: Int
        if options.numResults <= 0 || options.numResults > 20 {
            maxResults = 10
        } else {
            maxResults = options.numResults
        }

        let requestBody = TavilyRequest(
            query:             queryString,
            searchDepth:       searchDepth,
            maxResults:        maxResults,
            includeRawContent: includeRawContent,
            includeAnswer:     includeAnswer
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
        transport: HTTPTransport = HTTPTransport()
    ) -> TavilyBackend {
        TavilyBackend(
            apiKey:            config.enginesTavily.apiKey,
            searchDepth:       config.enginesTavily.searchDepth,
            includeRawContent: config.enginesTavily.includeRawContent,
            includeAnswer:     config.enginesTavily.includeAnswer,
            transport:         transport
        )
    }
}
