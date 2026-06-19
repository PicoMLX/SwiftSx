import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftSx

// MARK: - Helpers

/// Decode a JSON body `Data` into a [String: Any] dictionary (top level only).
private func decodeExaBody(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

/// Build a minimal valid Exa API JSON response body.
private func exaAPIJSON(results: [[String: String?]] = []) -> Data {
    let entries = results.map { dict -> String in
        let fields = dict.compactMap { k, v -> String? in
            guard let v else { return nil }
            return "\"\(k)\": \"\(v)\""
        }.joined(separator: ", ")
        return "{\(fields)}"
    }
    let body = "{\"results\": [\(entries.joined(separator: ", "))]}"
    return Data(body.utf8)
}

/// Build a minimal Exa MCP `tools/call` result with `structuredContent.results[]`.
///
/// `CallTool.Result.content` is a required field in the MCP SDK, so an empty
/// `content` array is always included alongside the structured payload.
private func exaMCPStructuredJSON(results: [[String: String]] = []) -> Data {
    let entries = results.map { dict in
        let fields = dict.map { k, v in "\"\(k)\": \"\(v)\"" }.joined(separator: ", ")
        return "{\(fields)}"
    }
    let body = """
    {
      "content": [],
      "structuredContent": {
        "results": [\(entries.joined(separator: ", "))]
      }
    }
    """
    return Data(body.utf8)
}

/// Build an Exa MCP `tools/call` result using `content[]` Markdown links.
private func exaMCPMarkdownContentJSON(text: String) -> Data {
    // Escape double-quotes and newlines for embedding in a JSON string literal.
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    let body = """
    {
      "content": [
        {"type": "text", "text": "\(escaped)"}
      ]
    }
    """
    return Data(body.utf8)
}

// MARK: - MCP SDK wire helpers
//
// The official MCP Swift SDK drives a three-message JSON-RPC lifecycle over
// HTTP: `initialize` → `notifications/initialized` → `tools/call`. Each request
// carries a freshly generated (random UUID) `id`, so a mock cannot return canned
// responses — it must parse each request and echo its `id` back, or the SDK's
// client never matches the response to its pending request and hangs.

/// A minimal valid `initialize` result body (the `result` field of the envelope).
private let mcpInitializeResultJSON = Data("""
{"protocolVersion":"2025-11-25","capabilities":{},"serverInfo":{"name":"exa-mock","version":"1.0.0"}}
""".utf8)

private extension URLRequest {
    /// The request body, falling back to draining `httpBodyStream` when
    /// `httpBody` is nil. `URLSession` converts bodies to a stream for
    /// upload/`bytes(for:)` requests, so the `URLProtocol` sees the stream.
    var sx_bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Serialize a parsed JSON-RPC `id` (string or number) back into a JSON token.
private func mcpIDToken(_ id: Any?) -> String {
    switch id {
    case let s as String: return "\"\(s)\""
    case let n as Int:    return "\(n)"
    default:              return "null"
    }
}

/// Wrap a `result` object in a JSON-RPC success envelope echoing `id`.
private func mcpResultEnvelope(id: Any?, result: Data) -> Data {
    let resultString = String(data: result, encoding: .utf8) ?? "{}"
    return Data("{\"jsonrpc\":\"2.0\",\"id\":\(mcpIDToken(id)),\"result\":\(resultString)}".utf8)
}

/// Build a method-aware `MockURLProtocol` handler that speaks the SDK's JSON-RPC
/// wire protocol: it answers `initialize` with a minimal valid result, accepts
/// `notifications/initialized`, and returns the supplied outcome for
/// `tools/call`, echoing each request's `id`.
///
/// - Parameters:
///   - toolCallStatus: HTTP status for the `tools/call` response (default 200).
///     For a non-2xx status the SDK throws on the status before reading the body.
///   - toolCallResult: the `tools/call` `result` object (used only for 2xx).
///   - capture: optional sink that receives the decoded `tools/call` arguments.
private func mcpHandler(
    toolCallStatus: Int = 200,
    toolCallResult: Data = exaMCPStructuredJSON(),
    capture: TestLockedBox<[String: Any]?>? = nil
) -> MockURLProtocol.Handler {
    return { request in
        let obj = (try? JSONSerialization.jsonObject(with: request.sx_bodyData)) as? [String: Any]
        let method = obj?["method"] as? String

        func respond(_ status: Int, _ data: Data) -> (HTTPURLResponse, Data) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        switch method {
        case "initialize":
            return respond(200, mcpResultEnvelope(id: obj?["id"], result: mcpInitializeResultJSON))
        case "notifications/initialized":
            return respond(202, Data())   // notification — no JSON-RPC response expected
        case "tools/call":
            if let capture, let params = obj?["params"] as? [String: Any] {
                capture.withLock { $0 = params["arguments"] as? [String: Any] }
            }
            guard (200...299).contains(toolCallStatus) else {
                return respond(toolCallStatus, Data("error".utf8))
            }
            return respond(toolCallStatus, mcpResultEnvelope(id: obj?["id"], result: toolCallResult))
        default:
            return respond(200, Data())
        }
    }
}

// MARK: - makeAPIRequest: body fields

@Suite struct ExaAPIRequestBodyTests {

    private let backend = ExaBackend(
        mode: "api",
        apiKey: "test-exa-key",
        numResults: 10
    )

    @Test func postMethodIsUsed() throws {
        let (req, _) = try backend.makeAPIRequest(SearchOptions(query: "swift"))
        #expect(req.method == .post)
    }

    @Test func endpointIsCorrect() throws {
        let (req, _) = try backend.makeAPIRequest(SearchOptions(query: "swift"))
        #expect(req.url?.absoluteString == "https://api.exa.ai/search")
    }

    @Test func bodyContainsQuery() throws {
        let (_, body) = try backend.makeAPIRequest(SearchOptions(query: "swift concurrency"))
        let dict = decodeExaBody(body)
        #expect(dict["query"] as? String == "swift concurrency")
    }

    @Test func bodySiteUsesIncludeDomainsWhenNonEmpty() throws {
        let options = SearchOptions(query: "swift", site: "github.com")
        let (_, body) = try backend.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        // The query is no longer site-prefixed; the domain goes to includeDomains.
        #expect(dict["query"] as? String == "swift")
        #expect(dict["includeDomains"] as? [String] == ["github.com"])
    }

    @Test func bodyIncludeDomainsAbsentWhenSiteEmpty() throws {
        let options = SearchOptions(query: "swift", site: "")
        let (_, body) = try backend.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        #expect(dict["query"] as? String == "swift")
        #expect(dict["includeDomains"] == nil)
    }

    @Test func bodyNumResultsClampedToExaMaximum() throws {
        let options = SearchOptions(query: "test", numResults: 500)
        let (_, body) = try backend.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        #expect(dict["numResults"] as? Int == 100)
    }

    @Test func numResultsFromOptionsWhenPositive() throws {
        let options = SearchOptions(query: "test", numResults: 5)
        let (_, body) = try backend.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        #expect(dict["numResults"] as? Int == 5)
    }

    @Test func numResultsFromBackendDefaultWhenOptionsIsZero() throws {
        // options.numResults == 0  → use backend.numResults (10)
        let b = ExaBackend(mode: "api", apiKey: "key", numResults: 7)
        let options = SearchOptions(query: "test", numResults: 0)
        let (_, body) = try b.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        #expect(dict["numResults"] as? Int == 7)
    }

    @Test func numResultsFallsBackToTenWhenBothAreZero() throws {
        // options.numResults == 0 AND backend.numResults == 0 → 10
        let b = ExaBackend(mode: "api", apiKey: "key", numResults: 0)
        let options = SearchOptions(query: "test", numResults: 0)
        let (_, body) = try b.makeAPIRequest(options)
        let dict = decodeExaBody(body)
        #expect(dict["numResults"] as? Int == 10)
    }

    @Test func bodyRequestsBoundedContentsText() throws {
        // Exa returns no text/summary unless `contents` is requested, so the body
        // must ask for page text — but bounded (maxCharacters), not unbounded
        // `text: true`, so a search doesn't pull full page bodies.
        let (_, body) = try backend.makeAPIRequest(SearchOptions(query: "swift"))
        let dict = decodeExaBody(body)
        let contents = dict["contents"] as? [String: Any]
        let text = contents?["text"] as? [String: Any]
        #expect(text?["maxCharacters"] as? Int == 2000)
    }
}

// MARK: - makeAPIRequest: headers

@Suite struct ExaAPIRequestHeaderTests {

    @Test func contentTypeHeaderIsJSON() throws {
        let backend = ExaBackend(mode: "api", apiKey: "key")
        let (req, _) = try backend.makeAPIRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.contentType] == "application/json")
    }

    @Test func acceptHeaderIsJSON() throws {
        let backend = ExaBackend(mode: "api", apiKey: "key")
        let (req, _) = try backend.makeAPIRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.accept] == "application/json")
    }

    @Test func xApiKeyHeaderContainsKey() throws {
        let backend = ExaBackend(mode: "api", apiKey: "my-exa-key")
        let (req, _) = try backend.makeAPIRequest(SearchOptions(query: "test"))
        let xApiKey = HTTPField.Name("x-api-key")!
        #expect(req.headerFields[xApiKey] == "my-exa-key")
    }
}

// MARK: - isAvailable per mode

@Suite struct ExaIsAvailableTests {

    @Test func apiModeAvailableWhenAPIKeyNonEmpty() {
        let b = ExaBackend(mode: "api", apiKey: "key", mcpURL: "")
        #expect(b.isAvailable)
    }

    @Test func apiModeUnavailableWhenAPIKeyEmpty() {
        let b = ExaBackend(mode: "api", apiKey: "", mcpURL: "https://mcp.example.com")
        #expect(!b.isAvailable)
    }

    @Test func mcpModeAvailableWhenMCPURLNonEmpty() {
        let b = ExaBackend(mode: "mcp", apiKey: "", mcpURL: "https://mcp.example.com")
        #expect(b.isAvailable)
    }

    @Test func mcpModeUnavailableWhenMCPURLEmpty() {
        let b = ExaBackend(mode: "mcp", apiKey: "key", mcpURL: "")
        #expect(!b.isAvailable)
    }

    @Test func autoModeAvailableWhenAPIKeyNonEmpty() {
        let b = ExaBackend(mode: "auto", apiKey: "key", mcpURL: "")
        #expect(b.isAvailable)
    }

    @Test func autoModeAvailableWhenMCPURLNonEmpty() {
        let b = ExaBackend(mode: "auto", apiKey: "", mcpURL: "https://mcp.example.com")
        #expect(b.isAvailable)
    }

    @Test func autoModeAvailableWhenBothConfigured() {
        let b = ExaBackend(mode: "auto", apiKey: "key", mcpURL: "https://mcp.example.com")
        #expect(b.isAvailable)
    }

    @Test func autoModeUnavailableWhenNeitherConfigured() {
        let b = ExaBackend(mode: "auto", apiKey: "", mcpURL: "")
        #expect(!b.isAvailable)
    }
}

// MARK: - search (API mode): happy path + status codes

@Suite(.serialized)
struct ExaAPISearchTests {

    private func makeBackend(apiKey: String = "test-key") -> ExaBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return ExaBackend(
            mode: "api",
            apiKey: apiKey,
            numResults: 10,
            transport: transport
        )
    }

    private func setHandler(status: Int, body: Data) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
    }

    // MARK: Happy path

    @Test func happyPathReturnsResults() async throws {
        let backend = makeBackend()
        let body = exaAPIJSON(results: [
            ["title": "Swift.org", "url": "https://swift.org", "text": "Swift language home"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
        #expect(results[0].content == "Swift language home")
        #expect(results[0].engine == "exa")
        #expect(results[0].engines == ["exa"])
    }

    @Test func happyPathPrefersTextOverSummary() async throws {
        let backend = makeBackend()
        let body = exaAPIJSON(results: [
            ["title": "Test", "url": "https://t.com", "text": "full text", "summary": "brief summary"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "full text")
    }

    @Test func happyPathFallsBackToSummaryWhenTextEmpty() async throws {
        let backend = makeBackend()
        // text is present but empty → use summary.
        let body = Data("""
        {"results": [{"title": "Test", "url": "https://t.com", "text": "", "summary": "brief summary"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "brief summary")
    }

    @Test func happyPathFallsBackToSummaryWhenTextMissing() async throws {
        let backend = makeBackend()
        // No `text` key at all → fall back to `summary`.
        let body = Data("""
        {"results": [{"title": "Test", "url": "https://t.com", "summary": "only summary"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "only summary")
    }

    @Test func happyPathEmptyContentWhenBothMissing() async throws {
        let backend = makeBackend()
        let body = Data("""
        {"results": [{"title": "No content", "url": "https://t.com"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "")
    }

    @Test func happyPathEmptyResultsArray() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: exaAPIJSON(results: []))

        let results = try await backend.search(SearchOptions(query: "xyzzy"))
        #expect(results.isEmpty)
    }

    @Test func happyPathMultipleResults() async throws {
        let backend = makeBackend()
        let body = exaAPIJSON(results: [
            ["title": "Alpha", "url": "https://a.example.com"],
            ["title": "Beta",  "url": "https://b.example.com"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 2)
        #expect(results[0].title == "Alpha")
        #expect(results[1].title == "Beta")
    }

    @Test func numResultsCapApplied() async throws {
        let backend = makeBackend()
        let body = exaAPIJSON(results: [
            ["title": "One", "url": "https://a.com"],
            ["title": "Two", "url": "https://b.com"],
            ["title": "Three", "url": "https://c.com"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test", numResults: 2))
        #expect(results.count == 2)
    }

    // MARK: Status → error code

    @Test func status401ThrowsAuthError() async throws {
        let backend = makeBackend()
        setHandler(status: 401, body: Data("Unauthorized".utf8))

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .auth)
            #expect(error.message.contains("401"))
            #expect(error.message.contains("EXA_API_KEY"))
        }
    }

    @Test func status403ThrowsAuthError() async throws {
        let backend = makeBackend()
        setHandler(status: 403, body: Data("Forbidden".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .auth)
            #expect(error.message.contains("403"))
        }
    }

    @Test func status429ThrowsRateLimitError() async throws {
        let backend = makeBackend()
        setHandler(status: 429, body: Data("Too Many Requests".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .rateLimit)
            #expect(error.message.contains("429"))
        }
    }

    @Test func status500ThrowsNetworkError() async throws {
        let backend = makeBackend()
        setHandler(status: 500, body: Data("Server Error".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .network)
            #expect(error.message.contains("500"))
        }
    }

    @Test func malformedJSONThrowsInvalidResponse() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: Data("not json".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test func unavailableAPIBackendThrowsWithoutNetwork() async throws {
        // API mode with no apiKey → unavailable.
        let backend = ExaBackend(mode: "api", apiKey: "")

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .unavailable)
        }
    }
}

// MARK: - search (MCP mode): structured content and markdown links

@Suite(.serialized)
struct ExaMCPSearchTests {

    private func makeBackend(mcpURL: String = "https://mcp.example.com") -> ExaBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return ExaBackend(
            mode:      "mcp",
            apiKey:    "",
            mcpURL:    mcpURL,
            mcpTool:   "exa-web-search",
            numResults: 10,
            transport:  transport
        )
    }

    // MARK: structuredContent path

    @Test func mcpStructuredContentResultsParsed() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallResult: exaMCPStructuredJSON(results: [
            ["title": "Swift Forums", "url": "https://forums.swift.org", "text": "Swift community"],
            ["title": "Swift Blog", "url": "https://swift.org/blog", "summary": "Official blog"],
        ]))

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 2)
        #expect(results[0].title == "Swift Forums")
        #expect(results[0].url == "https://forums.swift.org")
        #expect(results[0].content == "Swift community")
        #expect(results[0].engine == "exa")
        #expect(results[1].content == "Official blog")
    }

    @Test func mcpStructuredContentFirstNonEmptyPreference() async throws {
        let backend = makeBackend()
        // text is empty → content wins (content is still a required field).
        let resultJSON = Data("""
        {
          "content": [],
          "structuredContent": {
            "results": [{"title":"T","url":"https://t.com","text":"","content":"from content","summary":"from summary"}]
          }
        }
        """.utf8)
        MockURLProtocol.handler = mcpHandler(toolCallResult: resultJSON)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].content == "from content")
    }

    // MARK: Markdown link content[] path

    @Test func mcpMarkdownLinkContentParsed() async throws {
        let backend = makeBackend()
        let markdownText = """
                Here are results:
                [Swift.org](https://swift.org) - The home of Swift
                [Swift Forums](https://forums.swift.org) - Community discussions
                """
        MockURLProtocol.handler = mcpHandler(toolCallResult: exaMCPMarkdownContentJSON(text: markdownText))

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 2)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
        #expect(results[1].title == "Swift Forums")
        #expect(results[1].url == "https://forums.swift.org")
        #expect(results[0].engine == "exa")
    }

    @Test func mcpMarkdownLinkNoMatchYieldsEmpty() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(
            toolCallResult: exaMCPMarkdownContentJSON(text: "No links here at all.")
        )

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.isEmpty)
    }

    @Test func mcpNumResultsCapApplied() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallResult: exaMCPStructuredJSON(results: [
            ["title": "A", "url": "https://a.com"],
            ["title": "B", "url": "https://b.com"],
            ["title": "C", "url": "https://c.com"],
        ]))

        let results = try await backend.search(SearchOptions(query: "test", numResults: 2))
        #expect(results.count == 2)
    }

    // MARK: site forwarding (newly supported in MCP mode)

    @Test func mcpForwardsSiteAsIncludeDomains() async throws {
        let backend = makeBackend()
        let captured = TestLockedBox<[String: Any]?>(nil)
        MockURLProtocol.handler = mcpHandler(
            toolCallResult: exaMCPStructuredJSON(results: [["title": "x", "url": "https://x.com"]]),
            capture: captured
        )

        _ = try await backend.search(SearchOptions(query: "swift", site: "github.com", numResults: 5))

        let args = captured.withLock { $0 }
        #expect(args?["query"] as? String == "swift")
        #expect(args?["numResults"] as? Int == 5)
        #expect(args?["num_results"] as? Int == 5)
        #expect(args?["includeDomains"] as? [String] == ["github.com"])
    }

    @Test func mcpOmitsIncludeDomainsWhenSiteEmpty() async throws {
        let backend = makeBackend()
        let captured = TestLockedBox<[String: Any]?>(nil)
        MockURLProtocol.handler = mcpHandler(
            toolCallResult: exaMCPStructuredJSON(results: [["title": "x", "url": "https://x.com"]]),
            capture: captured
        )

        _ = try await backend.search(SearchOptions(query: "swift"))

        let args = captured.withLock { $0 }
        #expect(args?["query"] as? String == "swift")
        #expect(args?["includeDomains"] == nil)
    }

    // MARK: unparseable result

    @Test func mcpUnparseableResultThrowsInvalidResponse() async throws {
        // A 2xx response whose `result` does not match the tools/call shape (no
        // required `content` field) is unparseable → .invalidResponse.
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallResult: Data(#"{"unexpected":"shape"}"#.utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test func mcpMalformedStructuredContentThrowsInvalidResponse() async throws {
        // structuredContent is present but its `results` shape is wrong (a string,
        // not an array). This must surface as .invalidResponse, not silently fall
        // through to the (empty) Markdown path and "succeed" with no results.
        let backend = makeBackend()
        let resultJSON = Data(#"{"content":[],"structuredContent":{"results":"not-an-array"}}"#.utf8)
        MockURLProtocol.handler = mcpHandler(toolCallResult: resultJSON)

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    // MARK: unmatched JSON-RPC error (id: null) must time out, not hang
    //
    // A JSON-RPC error response with `id: null` (valid JSON-RPC — e.g. plan/auth
    // guidance) cannot be matched to the pending `tools/call` request, so the
    // SDK never resumes it. The request ceiling must surface a network error
    // instead of awaiting forever. `.timeLimit` is a backstop: if the ceiling
    // ever regresses, the test fails fast rather than hanging CI.

    @Test(.timeLimit(.minutes(1)))
    func mcpUnmatchedErrorResponseTimesOutInsteadOfHanging() async throws {
        // A 1s per-request timeout makes the operation ceiling ~3s (3 round trips).
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 1
        let transport = HTTPTransport(session: URLSession(configuration: config))
        let backend = ExaBackend(
            mode:       "mcp",
            apiKey:     "",
            mcpURL:     "https://mcp.example.com",
            mcpTool:    "exa-web-search",
            numResults: 10,
            transport:  transport
        )

        // initialize succeeds (id echoed); tools/call returns a JSON-RPC error
        // whose id is null — unmatchable to the pending request.
        MockURLProtocol.handler = { request in
            let obj = (try? JSONSerialization.jsonObject(with: request.sx_bodyData)) as? [String: Any]
            func respond(_ status: Int, _ data: Data) -> (HTTPURLResponse, Data) {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, data)
            }
            switch obj?["method"] as? String {
            case "initialize":
                return respond(200, mcpResultEnvelope(id: obj?["id"], result: mcpInitializeResultJSON))
            case "notifications/initialized":
                return respond(202, Data())
            case "tools/call":
                return respond(200, Data(#"{"jsonrpc":"2.0","error":{"code":-32000,"message":"plan limit"},"id":null}"#.utf8))
            default:
                return respond(200, Data())
            }
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError (timeout), not a hang or success")
        } catch let error as BackendError {
            #expect(error.code == .network)
        }
    }

    // MARK: MCP server status → error code
    //
    // `initialize` always succeeds; the status under test is returned on the
    // `tools/call` response. The SDK collapses HTTP status into MCPError, so the
    // class of failure is asserted via `error.code` (the exit-code contract).

    @Test func mcpStatus401ThrowsAuthError() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallStatus: 401)

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .auth)
        }
    }

    @Test func mcpStatus403ThrowsAuthError() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallStatus: 403)

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .auth)
        }
    }

    @Test func mcpStatus429ThrowsRateLimitError() async throws {
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallStatus: 429)

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .rateLimit)
        }
    }

    @Test func mcpStatus500ThrowsNetworkError() async throws {
        // Regression guard: genuine server errors stay classified as network.
        let backend = makeBackend()
        MockURLProtocol.handler = mcpHandler(toolCallStatus: 500)

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
            Issue.record("Expected a BackendError to be thrown")
        } catch let error as BackendError {
            #expect(error.code == .network)
            #expect(error.message.contains("500"))
        }
    }
}

// MARK: - search (auto mode): API-to-MCP fallback

@Suite(.serialized)
struct ExaAutoModeTests {

    @Test func autoModeUsesAPIWhenKeyPresent() async throws {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let backend = ExaBackend(
            mode:      "auto",
            apiKey:    "test-key",
            mcpURL:    "https://mcp.example.com",
            numResults: 10,
            transport:  transport
        )

        // Only one request (the API call) should be made.
        MockURLProtocol.handler = { request in
            let body = exaAPIJSON(results: [
                ["title": "From API", "url": "https://api.example.com"],
            ])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "From API")
    }

    @Test func autoModeFallsBackToMCPWhenAPIFails() async throws {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let backend = ExaBackend(
            mode:      "auto",
            apiKey:    "bad-key",
            mcpURL:    "https://mcp.example.com",
            numResults: 10,
            transport:  transport
        )

        // Dispatch by host: the API endpoint fails with 401; the MCP endpoint
        // speaks the SDK's JSON-RPC protocol (initialize → notification → call).
        let mcp = mcpHandler(toolCallResult: exaMCPStructuredJSON(results: [
            ["title": "From MCP", "url": "https://mcp.example.com"],
        ]))
        MockURLProtocol.handler = { request in
            if request.url?.host == "api.exa.ai" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("Unauthorized".utf8))
            }
            return try mcp(request)
        }

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "From MCP")
    }

    @Test func autoModeUsesMCPOnlyWhenNoAPIKey() async throws {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let backend = ExaBackend(
            mode:      "auto",
            apiKey:    "",
            mcpURL:    "https://mcp.example.com",
            numResults: 10,
            transport:  transport
        )

        // Lock-guarded counter so the @Sendable handler captures no mutable var.
        let requestCount = TestLockedBox(0)
        let mcp = mcpHandler(toolCallResult: exaMCPStructuredJSON(results: [
            ["title": "MCP Result", "url": "https://mcp.example.com"],
        ]))
        MockURLProtocol.handler = { request in
            requestCount.withLock { $0 += 1 }
            return try mcp(request)
        }

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "MCP Result")
        // No API call is made (no key). The MCP lifecycle is three POSTs:
        // initialize, notifications/initialized, and tools/call.
        #expect(requestCount.withLock { $0 } == 3)
    }

    @Test func autoModeThrowsWhenNeitherConfigured() async throws {
        let backend = ExaBackend(mode: "auto", apiKey: "", mcpURL: "")

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .unavailable)
        }
    }
}

// MARK: - Factory: ExaBackend.makeExa(from:transport:)

@Suite struct ExaFactoryTests {

    @Test func modePassedFromConfig() {
        var config = Config()
        config.enginesExa.mode = "mcp"
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.mode == "mcp")
    }

    @Test func apiKeyPassedFromConfig() {
        var config = Config()
        config.enginesExa.apiKey = "config-exa-key"
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.apiKey == "config-exa-key")
    }

    @Test func mcpURLPassedFromConfig() {
        var config = Config()
        config.enginesExa.mcpURL = "https://mcp.example.com"
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.mcpURL == "https://mcp.example.com")
    }

    @Test func mcpToolPassedFromConfig() {
        var config = Config()
        config.enginesExa.mcpTool = "custom-tool"
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.mcpTool == "custom-tool")
    }

    @Test func numResultsPassedFromConfig() {
        var config = Config()
        config.enginesExa.numResults = 20
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.numResults == 20)
    }

    @Test func emptyAPIKeyAndMCPURLYieldsUnavailableBackend() {
        var config = Config()
        config.enginesExa.apiKey = ""
        config.enginesExa.mcpURL = ""
        let backend = ExaBackend.makeExa(from: config)
        #expect(!backend.isAvailable)
    }

    @Test func nonEmptyAPIKeyYieldsAvailableBackendInAutoMode() {
        var config = Config()
        config.enginesExa.mode   = "auto"
        config.enginesExa.apiKey = "some-key"
        let backend = ExaBackend.makeExa(from: config)
        #expect(backend.isAvailable)
    }

    @Test func injectedTransportIsUsed() {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let config = Config()
        let backend = ExaBackend.makeExa(from: config, transport: transport)
        #expect(backend.transport.session === transport.session)
    }
}
