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
private func decodeJinaBody(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

/// Build a minimal valid Jina AI JSON response body.
private func jinaJSON(items: [[String: String]] = []) -> Data {
    let entries = items.map { dict in
        let fields = dict.map { k, v in "\"\(k)\": \"\(v)\"" }.joined(separator: ", ")
        return "{\(fields)}"
    }
    let body = "{\"code\": 200, \"data\": [\(entries.joined(separator: ", "))]}"
    return Data(body.utf8)
}

// MARK: - makeRequest: body fields

@Suite struct JinaMakeRequestBodyTests {

    private let backend = JinaBackend(
        apiKey: "test-jina-key",
        allowKeyless: false,
        baseURL: "https://s.jina.ai"
    )

    @Test func postMethodIsUsed() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "swift"))
        #expect(req.method == .post)
    }

    @Test func endpointUsesBaseURL() throws {
        let b = JinaBackend(apiKey: "key", baseURL: "https://custom.jina.ai")
        let (req, _) = try b.makeRequest(SearchOptions(query: "test"))
        #expect(req.url?.absoluteString == "https://custom.jina.ai")
    }

    @Test func trailingSlashTrimmedFromBaseURL() throws {
        let b = JinaBackend(apiKey: "key", baseURL: "https://s.jina.ai/")
        let (req, _) = try b.makeRequest(SearchOptions(query: "test"))
        #expect(req.url?.absoluteString == "https://s.jina.ai")
    }

    @Test func bodyContainsQuery() throws {
        let (_, body) = try backend.makeRequest(SearchOptions(query: "swift concurrency"))
        let dict = decodeJinaBody(body)
        #expect(dict["q"] as? String == "swift concurrency")
    }

    @Test func bodyDoesNotPrefixSiteToQuery() throws {
        // Jina uses X-Site header — NOT a site: prefix on the query.
        let options = SearchOptions(query: "swift", site: "github.com")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeJinaBody(body)
        let q = dict["q"] as? String ?? ""
        #expect(!q.hasPrefix("site:"))
        #expect(q == "swift")
    }

    @Test func bodyIncludesHlWhenLanguageNonEmpty() throws {
        let options = SearchOptions(query: "test", language: "en")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeJinaBody(body)
        #expect(dict["hl"] as? String == "en")
    }

    @Test func bodyOmitsHlWhenLanguageEmpty() throws {
        let options = SearchOptions(query: "test", language: "")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeJinaBody(body)
        #expect(dict["hl"] == nil)
    }

    @Test func bodyHlPassesThroughLocaleCode() throws {
        let options = SearchOptions(query: "test", language: "de-DE")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeJinaBody(body)
        #expect(dict["hl"] as? String == "de-DE")
    }
}

// MARK: - makeRequest: headers

@Suite struct JinaMakeRequestHeaderTests {

    @Test func acceptHeaderIsJSON() throws {
        let backend = JinaBackend(apiKey: "key")
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.accept] == "application/json")
    }

    @Test func contentTypeHeaderIsJSON() throws {
        let backend = JinaBackend(apiKey: "key")
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.contentType] == "application/json")
    }

    @Test func authorizationHeaderPresentWhenAPIKeyNonEmpty() throws {
        let backend = JinaBackend(apiKey: "my-jina-key")
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == "Bearer my-jina-key")
    }

    @Test func authorizationHeaderAbsentWhenAPIKeyEmpty() throws {
        let backend = JinaBackend(apiKey: "", allowKeyless: true)
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == nil)
    }

    @Test func xSiteHeaderPresentWhenSiteNonEmpty() throws {
        let backend = JinaBackend(apiKey: "key")
        let options = SearchOptions(query: "test", site: "github.com")
        let (req, _) = try backend.makeRequest(options)
        let xSite = HTTPField.Name("X-Site")!
        #expect(req.headerFields[xSite] == "https://github.com")
    }

    @Test func xSiteHeaderAbsentWhenSiteEmpty() throws {
        let backend = JinaBackend(apiKey: "key")
        let options = SearchOptions(query: "test", site: "")
        let (req, _) = try backend.makeRequest(options)
        let xSite = HTTPField.Name("X-Site")!
        #expect(req.headerFields[xSite] == nil)
    }

    @Test func xSiteHeaderPreservesExistingScheme() throws {
        let backend = JinaBackend(apiKey: "key")
        let options = SearchOptions(query: "test", site: "https://github.com")
        let (req, _) = try backend.makeRequest(options)
        let xSite = HTTPField.Name("X-Site")!
        #expect(req.headerFields[xSite] == "https://github.com")
    }

    @Test func xSiteHeaderPreservesHTTPScheme() throws {
        let backend = JinaBackend(apiKey: "key")
        let options = SearchOptions(query: "test", site: "http://internal.example.com")
        let (req, _) = try backend.makeRequest(options)
        let xSite = HTTPField.Name("X-Site")!
        #expect(req.headerFields[xSite] == "http://internal.example.com")
    }

    @Test func xSiteHeaderPrefixesHTTPSWhenNoScheme() throws {
        let backend = JinaBackend(apiKey: "key")
        let options = SearchOptions(query: "test", site: "example.com")
        let (req, _) = try backend.makeRequest(options)
        let xSite = HTTPField.Name("X-Site")!
        #expect(req.headerFields[xSite] == "https://example.com")
    }
}

// MARK: - isAvailable

@Suite struct JinaIsAvailableTests {

    @Test func trueWhenAPIKeyNonEmpty() {
        let backend = JinaBackend(apiKey: "some-key", allowKeyless: false)
        #expect(backend.isAvailable)
    }

    @Test func trueWhenKeylessAllowed() {
        let backend = JinaBackend(apiKey: "", allowKeyless: true)
        #expect(backend.isAvailable)
    }

    @Test func trueWhenBothAPIKeyAndKeylessSet() {
        let backend = JinaBackend(apiKey: "key", allowKeyless: true)
        #expect(backend.isAvailable)
    }

    @Test func falseWhenAPIKeyEmptyAndKeylessDisabled() {
        let backend = JinaBackend(apiKey: "", allowKeyless: false)
        #expect(!backend.isAvailable)
    }
}

// MARK: - search: happy path + status codes

@Suite(.serialized)
struct JinaSearchTests {

    private func makeBackend(
        apiKey: String = "test-key",
        allowKeyless: Bool = false
    ) -> JinaBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return JinaBackend(
            apiKey: apiKey,
            allowKeyless: allowKeyless,
            baseURL: "https://s.jina.ai",
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
        let body = jinaJSON(items: [
            ["title": "Swift.org", "url": "https://swift.org", "description": "Swift language home"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
        #expect(results[0].content == "Swift language home")
        #expect(results[0].engine == "jina")
        #expect(results[0].engines == ["jina"])
    }

    @Test func happyPathPrefersDescriptionOverContent() async throws {
        let backend = makeBackend()
        let body = Data("""
        {"data": [{"title": "T", "url": "https://t.com", "description": "desc value", "content": "long content here"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "desc value")
    }

    @Test func happyPathFallsBackToContentWhenDescriptionEmpty() async throws {
        let backend = makeBackend()
        let body = Data("""
        {"data": [{"title": "T", "url": "https://t.com", "description": "", "content": "fallback content"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "fallback content")
    }

    @Test func happyPathFallsBackToContentWhenDescriptionMissing() async throws {
        let backend = makeBackend()
        let body = Data("""
        {"data": [{"title": "T", "url": "https://t.com", "content": "only content"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content == "only content")
    }

    @Test func happyPathContentTruncatedToFiveHundredChars() async throws {
        let backend = makeBackend()
        let longContent = String(repeating: "x", count: 600)
        let body = Data("""
        {"data": [{"title": "T", "url": "https://t.com", "content": "\(longContent)"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content.count == 500)
    }

    @Test func happyPathContentExactly500CharsNotTruncated() async throws {
        let backend = makeBackend()
        let exactContent = String(repeating: "y", count: 500)
        let body = Data("""
        {"data": [{"title": "T", "url": "https://t.com", "content": "\(exactContent)"}]}
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results[0].content.count == 500)
    }

    @Test func happyPathEmptyDataArray() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: jinaJSON(items: []))

        let results = try await backend.search(SearchOptions(query: "xyzzy"))
        #expect(results.isEmpty)
    }

    @Test func happyPathMultipleResults() async throws {
        let backend = makeBackend()
        let body = jinaJSON(items: [
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
        let body = jinaJSON(items: [
            ["title": "One",   "url": "https://a.com"],
            ["title": "Two",   "url": "https://b.com"],
            ["title": "Three", "url": "https://c.com"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test", numResults: 2))
        #expect(results.count == 2)
    }

    @Test func numResultsCapNotAppliedWhenZero() async throws {
        let backend = makeBackend()
        let body = jinaJSON(items: [
            ["title": "One",   "url": "https://a.com"],
            ["title": "Two",   "url": "https://b.com"],
        ])
        setHandler(status: 200, body: body)

        // numResults == 0 → no cap, return all
        let results = try await backend.search(SearchOptions(query: "test", numResults: 0))
        #expect(results.count == 2)
    }

    @Test func status201AlsoDecodes() async throws {
        let backend = makeBackend()
        setHandler(status: 201, body: jinaJSON())
        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.isEmpty)
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
            #expect(error.message.contains("JINA_API_KEY"))
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

    @Test func status404ThrowsNetworkError() async throws {
        let backend = makeBackend()
        setHandler(status: 404, body: Data("Not Found".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .network)
            #expect(error.message.contains("404"))
        }
    }

    // MARK: Malformed JSON

    @Test func malformedJSONThrowsInvalidResponse() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: Data("this is not json".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    // MARK: Keyless operation

    @Test func keylessBackendSendsNoAuthHeader() async throws {
        let backend = makeBackend(apiKey: "", allowKeyless: true)
        let capturedRequest = TestLockedBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            capturedRequest.withLock { $0 = request }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jinaJSON())
        }

        _ = try await backend.search(SearchOptions(query: "test"))
        let authHeader = capturedRequest.withLock { $0?.value(forHTTPHeaderField: "Authorization") }
        #expect(authHeader == nil)
    }

    // MARK: Unavailable backend

    @Test func unavailableBackendThrowsWithoutNetwork() async throws {
        let backend = JinaBackend(apiKey: "", allowKeyless: false)

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

// MARK: - Factory: JinaBackend.makeJina(from:transport:)

@Suite struct JinaFactoryTests {

    @Test func apiKeyPassedFromConfig() {
        var config = Config()
        config.enginesJina.apiKey = "config-jina-key"
        let backend = JinaBackend.makeJina(from: config)
        #expect(backend.apiKey == "config-jina-key")
    }

    @Test func allowKeylessPassedFromConfig() {
        var config = Config()
        config.enginesJina.allowKeyless = false
        let backend = JinaBackend.makeJina(from: config)
        #expect(backend.allowKeyless == false)
    }

    @Test func baseURLPassedFromConfig() {
        var config = Config()
        config.enginesJina.baseURL = "https://custom.jina.ai"
        let backend = JinaBackend.makeJina(from: config)
        #expect(backend.baseURL == "https://custom.jina.ai")
    }

    @Test func emptyAPIKeyAndKeylessFalseYieldsUnavailableBackend() {
        var config = Config()
        config.enginesJina.apiKey       = ""
        config.enginesJina.allowKeyless = false
        let backend = JinaBackend.makeJina(from: config)
        #expect(!backend.isAvailable)
    }

    @Test func emptyAPIKeyAndKeylessTrueYieldsAvailableBackend() {
        var config = Config()
        config.enginesJina.apiKey       = ""
        config.enginesJina.allowKeyless = true
        let backend = JinaBackend.makeJina(from: config)
        #expect(backend.isAvailable)
    }

    @Test func nonEmptyAPIKeyYieldsAvailableBackend() {
        var config = Config()
        config.enginesJina.apiKey       = "some-key"
        config.enginesJina.allowKeyless = false
        let backend = JinaBackend.makeJina(from: config)
        #expect(backend.isAvailable)
    }

    @Test func injectedTransportIsUsed() {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let config = Config()
        let backend = JinaBackend.makeJina(from: config, transport: transport)
        #expect(backend.transport.session === transport.session)
    }
}
