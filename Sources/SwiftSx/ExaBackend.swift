import Foundation
import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ExaAPIRequest / ExaAPIResponse (private wire types)

/// The JSON body sent to the Exa `/search` API endpoint.
private struct ExaAPIRequest: Encodable {
    let query: String
    let numResults: Int
    /// Requests page contents for each result.
    ///
    /// Without a `contents` object the Exa `/search` endpoint returns only
    /// metadata (title/url) — no `text` or `summary` — so every mapped snippet
    /// would be empty. Asking for `text` populates the field the mapper reads.
    let contents: Contents
    /// Domain allow-list (Exa's `includeDomains`). When set, Exa restricts
    /// results to these domains — preferred over a lexical `site:` query prefix.
    let includeDomains: [String]?

    /// The `contents` sub-object; `text: true` asks Exa to include page text.
    struct Contents: Encodable {
        let text: Bool
    }

    enum CodingKeys: String, CodingKey {
        case query
        case numResults
        case contents
        case includeDomains
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(numResults, forKey: .numResults)
        try container.encode(contents, forKey: .contents)
        try container.encodeIfPresent(includeDomains, forKey: .includeDomains)
    }
}

/// The JSON envelope returned by the Exa `/search` API endpoint.
private struct ExaAPIResponse: Decodable {
    let results: [Item]?

    struct Item: Decodable {
        let title: String?
        let url: String?
        let text: String?
        let summary: String?
    }
}

// MARK: - ExaMCPResult (private wire types for MCP structured content)

/// Structured result item nested inside `structuredContent.results[]`.
private struct ExaMCPStructuredResult: Decodable {
    let title: String?
    let url: String?
    let text: String?
    let content: String?
    let summary: String?
    let snippet: String?
}

/// The `structuredContent` object that may appear in an MCP tool result.
private struct ExaMCPStructuredContent: Decodable {
    let results: [ExaMCPStructuredResult]?
}

/// A single item inside the MCP `content[]` array.
private struct ExaMCPContentItem: Decodable {
    let type: String?
    let text: String?
}

/// Top-level MCP `tools/call` result payload.
///
/// Either `structuredContent` carries the results, or they are embedded as
/// Markdown link text inside `content[]` items of `type == "text"`.
private struct ExaMCPToolResult: Decodable {
    let structuredContent: ExaMCPStructuredContent?
    let content: [ExaMCPContentItem]?
}

// MARK: - ExaBackend

/// An Exa Search backend supporting API mode, MCP mode, and automatic selection.
///
/// In `"auto"` mode the backend tries the REST API first (when `apiKey` is
/// non-empty) and falls back to MCP (when `mcpURL` is non-empty) if the API
/// call fails. `"api"` and `"mcp"` modes use only the respective transport.
public struct ExaBackend: SearchBackend {

    // MARK: - Properties

    /// The search mode: `"auto"` (default), `"api"`, or `"mcp"`.
    public let mode: String
    /// The Exa REST API key.
    public let apiKey: String
    /// The MCP server URL (used in `"mcp"` and `"auto"` modes).
    public let mcpURL: String
    /// The MCP tool name to invoke.
    public let mcpTool: String
    /// The default number of results to request when the caller does not specify.
    public let numResults: Int
    /// The transport layer (injectable for testing).
    let transport: HTTPTransport

    // MARK: - Init

    public init(
        mode: String = "auto",
        apiKey: String = "",
        mcpURL: String = "",
        mcpTool: String = "exa-web-search",
        numResults: Int = 10,
        transport: HTTPTransport = HTTPTransport()
    ) {
        self.mode       = mode
        self.apiKey     = apiKey
        self.mcpURL     = mcpURL
        self.mcpTool    = mcpTool
        self.numResults = numResults
        self.transport  = transport
    }

    // MARK: - SearchBackend

    public var name: String { "exa" }

    /// `true` when this backend has at least one viable transport configured.
    ///
    /// - `"api"`:  `apiKey` is non-empty.
    /// - `"mcp"`:  `mcpURL` is non-empty.
    /// - `"auto"`: either `apiKey` or `mcpURL` is non-empty.
    public var isAvailable: Bool {
        switch mode {
        case "api":  return !apiKey.isEmpty
        case "mcp":  return !mcpURL.isEmpty
        default:     return !apiKey.isEmpty || !mcpURL.isEmpty   // "auto" or unknown
        }
    }

    /// Perform a search using the configured mode.
    ///
    /// - Throws: `BackendError(.unavailable, …)` when `isAvailable` is `false`.
    /// - Throws: `BackendError` with an appropriate code on any HTTP or decode failure.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        guard isAvailable else {
            throw BackendError(
                backend: "exa",
                code: .unavailable,
                message: "exa is not configured — set EXA_API_KEY or engines_exa.mcp_url"
            )
        }

        switch mode {
        case "api":
            return try await searchAPI(options)
        case "mcp":
            return try await searchMCP(options)
        default:
            // "auto": try API first, fall back to MCP on failure.
            return try await searchAuto(options)
        }
    }

    // MARK: - Private: mode dispatch

    /// Execute in `"auto"` mode: REST API when apiKey is set, MCP as fallback.
    private func searchAuto(_ options: SearchOptions) async throws -> [SearchResult] {
        if !apiKey.isEmpty {
            do {
                return try await searchAPI(options)
            } catch is CancellationError {
                throw CancellationError()
            } catch let sx as SxError {
                throw sx
            } catch {
                // API failed; fall through to MCP if available.
                if !mcpURL.isEmpty {
                    return try await searchMCP(options)
                }
                throw error
            }
        }
        if !mcpURL.isEmpty {
            return try await searchMCP(options)
        }
        // Should be unreachable if isAvailable is correct.
        throw BackendError(
            backend: "exa",
            code: .unavailable,
            message: "exa is not configured — set EXA_API_KEY or engines_exa.mcp_url"
        )
    }

    // MARK: - API mode

    /// Perform a search against the Exa REST API.
    private func searchAPI(_ options: SearchOptions) async throws -> [SearchResult] {
        let (request, bodyData) = try makeAPIRequest(options)

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
                backend: "exa",
                code: .network,
                message: "exa request failed: \(error)"
            )
        }

        let status = response.status.code
        switch status {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(ExaAPIResponse.self, from: data)
                let mapped = (decoded.results ?? []).map { item -> SearchResult in
                    // Prefer `text`; fall back to `summary`; else empty.
                    let resolvedContent: String
                    if let t = item.text, !t.isEmpty {
                        resolvedContent = t
                    } else {
                        resolvedContent = item.summary ?? ""
                    }
                    return SearchResult(
                        title:   item.title ?? "",
                        url:     item.url   ?? "",
                        content: resolvedContent,
                        engine:  "exa",
                        engines: ["exa"]
                    )
                }
                if options.numResults > 0, mapped.count > options.numResults {
                    return Array(mapped.prefix(options.numResults))
                }
                return mapped
            } catch {
                throw BackendError(
                    backend: "exa",
                    code: .invalidResponse,
                    message: "exa returned a response that could not be parsed"
                )
            }
        case 401, 403:
            throw BackendError(
                backend: "exa",
                code: .auth,
                message: "exa rejected the request (HTTP \(status)) — check the Exa API key (EXA_API_KEY)"
            )
        case 429:
            throw BackendError(
                backend: "exa",
                code: .rateLimit,
                message: "exa is rate limiting (HTTP 429) — back off and retry"
            )
        default:
            throw BackendError(
                backend: "exa",
                code: .network,
                message: "exa returned HTTP \(status)"
            )
        }
    }

    // MARK: - Request construction (internal for testability)

    /// Build the `HTTPRequest` and JSON body for the Exa REST API.
    ///
    /// This is factored out of `searchAPI(_:)` so tests can assert the URL,
    /// method, headers, and body without touching the network.
    ///
    /// - Throws: `BackendError(.network, …)` when the endpoint URL cannot be
    ///   built or the body cannot be encoded.
    func makeAPIRequest(_ options: SearchOptions) throws -> (HTTPRequest, Data) {
        guard let url = URL(string: "https://api.exa.ai/search") else {
            throw BackendError(
                backend: "exa",
                code: .network,
                message: "exa request failed: could not build endpoint URL"
            )
        }

        // site restriction — use Exa's `includeDomains` allow-list rather than a
        // lexical `site:` query prefix.
        let includeDomains: [String]? = options.site.isEmpty ? nil : [options.site]

        // numResults resolution: options > backend default > 10, then clamp to
        // Exa's documented maximum of 100.
        let resolved: Int
        if options.numResults > 0 {
            resolved = options.numResults
        } else if numResults > 0 {
            resolved = numResults
        } else {
            resolved = 10
        }
        let n = min(resolved, 100)

        let requestBody = ExaAPIRequest(
            query: options.query,
            numResults: n,
            contents: .init(text: true),
            includeDomains: includeDomains
        )
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(requestBody)
        } catch {
            throw BackendError(
                backend: "exa",
                code: .network,
                message: "exa request failed: could not encode request body: \(error)"
            )
        }

        var request = HTTPRequest(method: .post, url: url)
        request.headerFields[.contentType] = "application/json"
        request.headerFields[.accept] = "application/json"
        request.headerFields[.xApiKey] = apiKey

        return (request, bodyData)
    }

    // MARK: - MCP mode

    /// Perform a search via the MCP JSON-RPC server.
    private func searchMCP(_ options: SearchOptions) async throws -> [SearchResult] {
        let client = MCPHTTPClient(urlString: mcpURL, transport: transport)

        // Best-effort handshake; errors are intentionally swallowed.
        await client.initialize()

        // Resolve numResults identically to API mode.
        let n: Int
        if options.numResults > 0 {
            n = options.numResults
        } else if numResults > 0 {
            n = numResults
        } else {
            n = 10
        }

        let args = MCPToolCallArguments(query: options.query, numResults: n)
        let toolResult: ExaMCPToolResult
        do {
            toolResult = try await client.callTool(name: mcpTool, arguments: args, responseType: ExaMCPToolResult.self)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sx as SxError {
            throw sx
        } catch let be as BackendError {
            throw be
        } catch {
            throw BackendError(
                backend: "exa",
                code: .network,
                message: "exa MCP request failed: \(error)"
            )
        }

        // Parse the tool result — try structuredContent first, then markdown links.
        let results = parseMCPResult(toolResult)

        if options.numResults > 0, results.count > options.numResults {
            return Array(results.prefix(options.numResults))
        }
        return results
    }

    // MARK: - MCP result parsing

    /// Parse a decoded `ExaMCPToolResult` into ``SearchResult`` values.
    ///
    /// Two strategies are tried in order:
    /// 1. `structuredContent.results[]` — preferred when present; each item's
    ///    content is the first non-empty of `text`, `content`, `summary`, `snippet`.
    /// 2. `content[]` items of `type == "text"` — scan the concatenated text for
    ///    Markdown links `[title](url)` via `NSRegularExpression`.
    private func parseMCPResult(_ toolResult: ExaMCPToolResult) -> [SearchResult] {
        if let structured = toolResult.structuredContent,
           let items = structured.results,
           !items.isEmpty {
            return items.map { item in
                let resolvedContent = firstNonEmpty(item.text, item.content, item.summary, item.snippet)
                return SearchResult(
                    title:   item.title ?? "",
                    url:     item.url   ?? "",
                    content: resolvedContent,
                    engine:  "exa",
                    engines: ["exa"]
                )
            }
        }

        // Fall back: scan content[] text items for Markdown links.
        if let contentItems = toolResult.content {
            let combinedText = contentItems
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined(separator: "\n")
            return extractMarkdownLinks(from: combinedText)
        }

        return []
    }

    /// Return the first argument that is non-nil and non-empty, or `""`.
    private func firstNonEmpty(_ candidates: String?...) -> String {
        for candidate in candidates {
            if let s = candidate, !s.isEmpty { return s }
        }
        return ""
    }

    /// Extract `[title](https://url)` pairs from `text` using `NSRegularExpression`.
    private func extractMarkdownLinks(from text: String) -> [SearchResult] {
        // Pattern matches [title](https?://url) — URL ends at the closing paren.
        guard let regex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\((https?://[^)]+)\)"#
        ) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> SearchResult? in
            guard match.numberOfRanges == 3 else { return nil }
            let titleRange = match.range(at: 1)
            let urlRange   = match.range(at: 2)
            guard titleRange.location != NSNotFound,
                  urlRange.location   != NSNotFound
            else { return nil }
            let title = nsText.substring(with: titleRange)
            let url   = nsText.substring(with: urlRange)
            return SearchResult(
                title:   title,
                url:     url,
                content: "",
                engine:  "exa",
                engines: ["exa"]
            )
        }
    }
}

// MARK: - HTTPField.Name extensions for Exa

private extension HTTPField.Name {
    /// The `x-api-key` header required by the Exa REST API.
    static let xApiKey = HTTPField.Name("x-api-key")!
}

// MARK: - Factory (builds an ExaBackend from Config)

extension ExaBackend {
    /// Build an ``ExaBackend`` from a loaded `Config`.
    ///
    /// - Parameters:
    ///   - config: The loaded and normalised configuration.
    ///   - transport: The HTTP transport to inject (default: shared session with
    ///     configured timeout).
    /// - Returns: An ``ExaBackend`` configured from `config.enginesExa`.
    public static func makeExa(
        from config: Config,
        transport: HTTPTransport? = nil
    ) -> ExaBackend {
        ExaBackend(
            mode:       config.enginesExa.mode,
            apiKey:     config.enginesExa.apiKey,
            mcpURL:     config.enginesExa.mcpURL,
            mcpTool:    config.enginesExa.mcpTool,
            numResults: config.enginesExa.numResults,
            transport:  transport ?? HTTPTransport(timeout: config.timeout)
        )
    }
}
