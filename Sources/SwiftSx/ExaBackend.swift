import Foundation
import HTTPTypes
import HTTPTypesFoundation
import MCP
import ShellKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ExaAPIRequest / ExaAPIResponse (private wire types)

/// The JSON body sent to the Exa `/search` API endpoint.
private struct ExaAPIRequest: Encodable {
    /// Upper bound on page-text characters requested per result.
    ///
    /// Unbounded `text` can return whole page bodies (megabytes for long pages),
    /// which the JSON / clean renderers emit verbatim. Bounding the *fetch* keeps
    /// a search lightweight; the plain renderer additionally caps display.
    static let maxTextCharacters = 2000

    let query: String
    let numResults: Int
    /// Requests page contents for each result.
    ///
    /// Without a `contents` object the Exa `/search` endpoint returns only
    /// metadata (title/url) — no `text` or `summary` — so every mapped snippet
    /// would be empty. Asking for bounded `text` populates the field the mapper
    /// reads without pulling full page bodies.
    let contents: Contents
    /// Domain allow-list (Exa's `includeDomains`). When set, Exa restricts
    /// results to these domains — preferred over a lexical `site:` query prefix.
    let includeDomains: [String]?

    /// The `contents` sub-object. `text.maxCharacters` bounds the page text Exa
    /// returns per result (vs. unbounded `text: true`).
    struct Contents: Encodable {
        let text: Text
        struct Text: Encodable {
            let maxCharacters: Int
        }
    }
    // Encoding is compiler-synthesized: the stored property names already match
    // the Exa API keys (query/numResults/contents/includeDomains), and the
    // synthesized encoder uses encodeIfPresent for the optional includeDomains
    // (so it is omitted when nil).
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
///
/// The MCP SDK surfaces `structuredContent` as an untyped ``MCP/Value``; we
/// re-encode that value and decode it into this concrete shape so the existing
/// result-mapping logic is preserved unchanged.
private struct ExaMCPStructuredContent: Decodable {
    let results: [ExaMCPStructuredResult]?
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

        let (data, response): (Data, HTTPTypes.HTTPResponse)
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
    func makeAPIRequest(_ options: SearchOptions) throws -> (HTTPTypes.HTTPRequest, Data) {
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
            contents: .init(text: .init(maxCharacters: ExaAPIRequest.maxTextCharacters)),
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

        var request = HTTPTypes.HTTPRequest(method: .post, url: url)
        request.headerFields[.contentType] = "application/json"
        request.headerFields[.accept] = "application/json"
        request.headerFields[.xApiKey] = apiKey

        return (request, bodyData)
    }

    // MARK: - MCP mode

    /// Perform a search via the Exa MCP server using the official MCP Swift SDK.
    ///
    /// The SDK's ``MCP/Client`` + ``MCP/HTTPClientTransport`` drive the JSON-RPC
    /// lifecycle: `connect(transport:)` performs `initialize` and emits
    /// `notifications/initialized`, then ``MCP/Client/callTool(name:arguments:meta:)``
    /// issues `tools/call`. We translate the SDK's result and error surface back
    /// onto SwiftSx's ``SearchResult`` / ``BackendError`` contracts.
    ///
    /// `streaming: false` selects a plain request/response POST per call (no SSE),
    /// which is both simpler to reason about and trivial to mock in tests.
    private func searchMCP(_ options: SearchOptions) async throws -> [SearchResult] {
        guard let url = URL(string: mcpURL) else {
            throw BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: invalid MCP URL '\(mcpURL)'"
            )
        }

        // API mode gates every request through the ShellKit sandbox (via
        // `HTTPTransport.send`). The SDK transport owns its own URLSession and
        // bypasses that gate, so authorize the endpoint here to preserve the
        // fail-closed sandbox semantics (a denial surfaces as `.refused`, exit 3).
        do {
            try await Shell.authorize(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SxError(.refused, "request to \(url.host ?? url.absoluteString) was refused by the sandbox: \(error)")
        }

        // Resolve numResults identically to API mode (options > backend default > 10).
        let n: Int
        if options.numResults > 0 {
            n = options.numResults
        } else if numResults > 0 {
            n = numResults
        } else {
            n = 10
        }

        // Tool arguments. Exa's tool accepts both `numResults` (camelCase) and
        // `num_results` (snake_case); send both for compatibility. Forward `site`
        // as an `includeDomains` allow-list, mirroring API mode (previously MCP
        // mode dropped the site restriction).
        var arguments: [String: Value] = [
            "query":       .string(options.query),
            "numResults":  .int(n),
            "num_results": .int(n),
        ]
        if !options.site.isEmpty {
            arguments["includeDomains"] = .array([.string(options.site)])
        }

        // Reuse the injected transport's URLSession configuration so that the
        // request timeout (production) and `MockURLProtocol` (tests) both flow
        // into the SDK transport's own session.
        let configuration = transport.session.configuration
        let mcpTransport = HTTPClientTransport(
            endpoint: url,
            configuration: configuration,
            streaming: false
        )
        let client = Client(name: "sx", version: SxVersion.current)

        // Bound the whole exchange. A misbehaving MCP server can return a
        // JSON-RPC error whose `id` is `null` (valid JSON-RPC, e.g. plan/auth
        // guidance from Exa's hosted server); the SDK cannot match that to the
        // pending `tools/call` request, so `context.value` would await forever.
        // On timeout, `disconnect()` fails every pending request — unblocking
        // that await — and we surface a network error. The ceiling follows the
        // configured per-request timeout (production), defaulting to 60s.
        let requestTimeout = configuration.timeoutIntervalForRequest
        let ceilingSeconds = (requestTimeout.isFinite && requestTimeout > 0) ? requestTimeout : 60
        let tool = mcpTool
        let args = arguments

        let result: CallTool.Result
        do {
            result = try await withThrowingTaskGroup(of: CallTool.Result.self) { group in
                group.addTask {
                    try await client.connect(transport: mcpTransport)
                    // The RequestContext overload of `callTool`: unlike the tuple
                    // overload it preserves `structuredContent`, Exa's primary path.
                    let context: RequestContext<CallTool.Result> =
                        try await client.callTool(name: tool, arguments: args)
                    return try await context.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(ceilingSeconds * 1_000_000_000))
                    // Fail any never-matched pending request so the operation
                    // task above unblocks and the group can tear down.
                    await client.disconnect()
                    throw BackendError(
                        backend: "exa-mcp",
                        code: .network,
                        message: "exa MCP request timed out after \(Int(ceilingSeconds))s without a matching response"
                    )
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw BackendError(
                        backend: "exa-mcp",
                        code: .invalidResponse,
                        message: "exa MCP returned a response that could not be parsed"
                    )
                }
                return first
            }
        } catch {
            await client.disconnect()
            throw mapMCPError(error)
        }
        await client.disconnect()

        // Parse the tool result — try structuredContent first, then markdown links.
        let results = parseMCPResult(structuredContent: result.structuredContent, content: result.content)

        if options.numResults > 0, results.count > options.numResults {
            return Array(results.prefix(options.numResults))
        }
        return results
    }

    // MARK: - MCP error mapping

    /// Map an error thrown by the MCP SDK onto SwiftSx's error contract.
    ///
    /// Cancellation, sandbox refusals (``SxError``), and already-classified
    /// ``BackendError`` values pass through unchanged; ``MCP/MCPError`` is
    /// classified by ``mapMCPProtocolError(_:)``; transport-level `URLError`s are
    /// network failures; anything else (notably the SDK's internal type-mismatch
    /// error for a 2xx response whose result did not match the `tools/call`
    /// shape) is treated as an unparseable response.
    private func mapMCPError(_ error: Error) -> Error {
        switch error {
        case is CancellationError:
            return error          // propagate the original; preserves any context
        case let sx as SxError:
            return sx
        case let be as BackendError:
            return be
        case let mcp as MCPError:
            return mapMCPProtocolError(mcp)
        case let urlError as URLError:
            return BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: \(urlError.localizedDescription)"
            )
        default:
            return BackendError(
                backend: "exa-mcp",
                code: .invalidResponse,
                message: "exa MCP returned a response that could not be parsed"
            )
        }
    }

    /// Classify an ``MCP/MCPError`` into a ``BackendError``.
    ///
    /// The SDK's HTTP transport collapses every non-2xx status into
    /// `MCPError.internalError(detail)` with a fixed detail string (see
    /// `HTTPClientTransport.processHTTPResponse` / `mapAuthenticationChallengeError`):
    /// 401 → "Authentication required", 403 → "Access forbidden",
    /// 429 → "Too many requests", 5xx → "Server error: <code>", etc. There is no
    /// structured status code to read, so the class of failure is recovered from
    /// that detail string. The SDK is pinned `.upToNextMinor` so these strings
    /// cannot shift without an opt-in version bump.
    private func mapMCPProtocolError(_ error: MCPError) -> BackendError {
        switch error {
        case .internalError(let detail):
            let d = detail ?? ""
            if d.contains("Authentication required") || d.contains("Access forbidden") {
                return BackendError(
                    backend: "exa-mcp",
                    code: .auth,
                    message: "exa MCP server rejected the request (\(d)) — check the MCP URL or its credentials (engines_exa.mcp_url)"
                )
            }
            if d.contains("Too many requests") {
                return BackendError(
                    backend: "exa-mcp",
                    code: .rateLimit,
                    message: "exa MCP server is rate limiting (too many requests) — back off and retry"
                )
            }
            return BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP server returned an error: \(d)"
            )
        case .parseError:
            return BackendError(
                backend: "exa-mcp",
                code: .invalidResponse,
                message: "exa MCP returned a response that could not be parsed"
            )
        default:
            return BackendError(
                backend: "exa-mcp",
                code: .network,
                message: "exa MCP request failed: \(error.errorDescription ?? "\(error)")"
            )
        }
    }

    // MARK: - MCP result parsing

    /// Parse an MCP `tools/call` result into ``SearchResult`` values.
    ///
    /// Two strategies are tried in order:
    /// 1. `structuredContent.results[]` — preferred when present; each item's
    ///    content is the first non-empty of `text`, `content`, `summary`, `snippet`.
    ///    The SDK exposes `structuredContent` as an untyped ``MCP/Value``, so it is
    ///    re-encoded and decoded into ``ExaMCPStructuredContent``.
    /// 2. `content[]` text items — scan the concatenated text for Markdown links
    ///    `[title](url)` via `NSRegularExpression`.
    private func parseMCPResult(structuredContent: Value?, content: [Tool.Content]) -> [SearchResult] {
        if let structuredContent,
           let structured = decodeStructuredContent(structuredContent),
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

        // Fall back: scan text content items for Markdown links.
        let combinedText = content
            .compactMap { item -> String? in
                if case .text(let text, _, _) = item { return text }
                return nil
            }
            .joined(separator: "\n")
        return extractMarkdownLinks(from: combinedText)
    }

    /// Re-encode an MCP ``MCP/Value`` and decode it into ``ExaMCPStructuredContent``.
    ///
    /// `Value` is `Codable`, so a round-trip through JSON recovers the concrete
    /// shape without hand-walking the enum.
    private func decodeStructuredContent(_ value: Value) -> ExaMCPStructuredContent? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ExaMCPStructuredContent.self, from: data)
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
