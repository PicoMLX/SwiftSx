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
private func decodeTavilyBody(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

/// Build a minimal valid Tavily JSON response body.
private func tavilyJSON(results: [[String: Any]] = []) -> Data {
    let obj: [String: Any] = ["results": results]
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
        return Data()
    }
    return data
}

/// Build a Tavily JSON result item.
private func tavilyItem(
    title: String = "Title",
    url: String = "https://example.com",
    content: String = "snippet",
    rawContent: String? = nil,
    score: Double = 0.9
) -> [String: Any] {
    var item: [String: Any] = [
        "title": title,
        "url": url,
        "content": content,
        "score": score,
    ]
    if let raw = rawContent {
        item["raw_content"] = raw
    }
    return item
}

// MARK: - makeRequest: body fields and headers

@Suite struct TavilyMakeRequestTests {

    private let backend = TavilyBackend(
        apiKey: "test-tvly-key",
        searchDepth: "basic",
        includeRawContent: false,
        includeAnswer: false
    )

    @Test func postMethodIsUsed() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "swift"))
        #expect(req.method == .post)
    }

    @Test func endpointIsCorrect() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "swift"))
        #expect(req.url?.absoluteString == "https://api.tavily.com/search")
    }

    @Test func contentTypeHeaderIsJSON() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.contentType] == "application/json")
    }

    @Test func authorizationHeaderIsBearerToken() throws {
        let b = TavilyBackend(apiKey: "my-tavily-key")
        let (req, _) = try b.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == "Bearer my-tavily-key")
    }

    @Test func bodyContainsQuery() throws {
        let (_, body) = try backend.makeRequest(SearchOptions(query: "swift concurrency"))
        let dict = decodeTavilyBody(body)
        #expect(dict["query"] as? String == "swift concurrency")
    }

    @Test func bodySitePrefixAddedWhenNonEmpty() throws {
        let options = SearchOptions(query: "swift", site: "github.com")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["query"] as? String == "site:github.com swift")
    }

    @Test func bodySitePrefixOmittedWhenEmpty() throws {
        let options = SearchOptions(query: "swift", site: "")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["query"] as? String == "swift")
    }

    @Test func bodyMaxResultsDefaultsTenWhenZero() throws {
        let options = SearchOptions(query: "test", numResults: 0)
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["max_results"] as? Int == 10)
    }

    @Test func bodyMaxResultsDefaultsTenWhenNegative() throws {
        let options = SearchOptions(query: "test", numResults: -1)
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["max_results"] as? Int == 10)
    }

    @Test func bodyMaxResultsClampsToTwentyWhenExceedsTwenty() throws {
        let options = SearchOptions(query: "test", numResults: 25)
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["max_results"] as? Int == 20)
    }

    @Test func bodyMaxResultsPassedThroughWhenInRange() throws {
        let options = SearchOptions(query: "test", numResults: 7)
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["max_results"] as? Int == 7)
    }

    @Test func bodyMaxResultsAtUpperBoundAllowed() throws {
        let options = SearchOptions(query: "test", numResults: 20)
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["max_results"] as? Int == 20)
    }

    @Test func bodySearchDepthPassedThrough() throws {
        let b = TavilyBackend(apiKey: "key", searchDepth: "advanced")
        let (_, body) = try b.makeRequest(SearchOptions(query: "test"))
        let dict = decodeTavilyBody(body)
        #expect(dict["search_depth"] as? String == "advanced")
    }

    @Test func bodyIncludeRawContentFalse() throws {
        let b = TavilyBackend(apiKey: "key", includeRawContent: false)
        let (_, body) = try b.makeRequest(SearchOptions(query: "test"))
        let dict = decodeTavilyBody(body)
        #expect(dict["include_raw_content"] as? Bool == false)
    }

    @Test func bodyIncludeRawContentTrue() throws {
        let b = TavilyBackend(apiKey: "key", includeRawContent: true)
        let (_, body) = try b.makeRequest(SearchOptions(query: "test"))
        let dict = decodeTavilyBody(body)
        #expect(dict["include_raw_content"] as? Bool == true)
    }

    @Test func bodyIncludeAnswerFalse() throws {
        let b = TavilyBackend(apiKey: "key", includeAnswer: false)
        let (_, body) = try b.makeRequest(SearchOptions(query: "test"))
        let dict = decodeTavilyBody(body)
        #expect(dict["include_answer"] as? Bool == false)
    }

    @Test func bodyIncludeAnswerTrue() throws {
        let b = TavilyBackend(apiKey: "key", includeAnswer: true)
        let (_, body) = try b.makeRequest(SearchOptions(query: "test"))
        let dict = decodeTavilyBody(body)
        #expect(dict["include_answer"] as? Bool == true)
    }
}

// MARK: - isAvailable

@Suite struct TavilyIsAvailableTests {

    @Test func trueWhenAPIKeyNonEmpty() {
        let backend = TavilyBackend(apiKey: "some-key")
        #expect(backend.isAvailable)
    }

    @Test func falseWhenAPIKeyEmpty() {
        let backend = TavilyBackend(apiKey: "")
        #expect(!backend.isAvailable)
    }
}

// MARK: - search: happy path + status codes

@Suite(.serialized)
struct TavilySearchTests {

    private func makeBackend(
        apiKey: String = "test-key",
        includeRawContent: Bool = false
    ) -> TavilyBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return TavilyBackend(
            apiKey: apiKey,
            searchDepth: "basic",
            includeRawContent: includeRawContent,
            includeAnswer: false,
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
        let body = tavilyJSON(results: [
            tavilyItem(title: "Swift.org", url: "https://swift.org", content: "Swift language home"),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
        #expect(results[0].content == "Swift language home")
        #expect(results[0].engine == "tavily")
        #expect(results[0].engines == ["tavily"])
    }

    @Test func happyPathEmptyResultsArray() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: tavilyJSON(results: []))

        let results = try await backend.search(SearchOptions(query: "xyzzy"))
        #expect(results.isEmpty)
    }

    @Test func happyPathMultipleResults() async throws {
        let backend = makeBackend()
        let body = tavilyJSON(results: [
            tavilyItem(title: "Alpha", url: "https://a.example.com"),
            tavilyItem(title: "Beta",  url: "https://b.example.com"),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 2)
        #expect(results[0].title == "Alpha")
        #expect(results[1].title == "Beta")
    }

    // MARK: raw_content vs content selection

    @Test func rawContentUsedWhenIncludeRawContentTrueAndRawNonEmpty() async throws {
        let backend = makeBackend(includeRawContent: true)
        let body = tavilyJSON(results: [
            tavilyItem(content: "short snippet", rawContent: "full raw page content"),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].content == "full raw page content")
    }

    @Test func contentUsedWhenIncludeRawContentFalse() async throws {
        let backend = makeBackend(includeRawContent: false)
        let body = tavilyJSON(results: [
            tavilyItem(content: "short snippet", rawContent: "full raw page content"),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].content == "short snippet")
    }

    @Test func contentUsedWhenRawContentNil() async throws {
        let backend = makeBackend(includeRawContent: true)
        let body = tavilyJSON(results: [
            tavilyItem(content: "only snippet", rawContent: nil),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].content == "only snippet")
    }

    @Test func contentUsedWhenRawContentEmpty() async throws {
        let backend = makeBackend(includeRawContent: true)
        let body = tavilyJSON(results: [
            tavilyItem(content: "only snippet", rawContent: ""),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].content == "only snippet")
    }

    @Test func status201AlsoDecodes() async throws {
        let backend = makeBackend()
        setHandler(status: 201, body: tavilyJSON())
        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.isEmpty)
    }

    // MARK: Status → error code mapping

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
            #expect(error.message.contains("TAVILY_API_KEY"))
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
        setHandler(status: 500, body: Data("Internal Server Error".utf8))

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

    // MARK: Unavailable backend throws

    @Test func unavailableBackendThrowsWithoutNetwork() async throws {
        let backend = TavilyBackend(apiKey: "")

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .unavailable)
            #expect(error.message.contains("TAVILY_API_KEY"))
        }
    }
}

// MARK: - Factory: TavilyBackend.makeTavily(from:transport:)

@Suite struct TavilyFactoryTests {

    @Test func apiKeyPassedFromConfig() {
        var config = Config()
        config.enginesTavily.apiKey = "config-tavily-key"
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(backend.apiKey == "config-tavily-key")
    }

    @Test func searchDepthPassedFromConfig() {
        var config = Config()
        config.enginesTavily.searchDepth = "advanced"
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(backend.searchDepth == "advanced")
    }

    @Test func includeRawContentPassedFromConfig() {
        var config = Config()
        config.enginesTavily.includeRawContent = true
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(backend.includeRawContent == true)
    }

    @Test func includeAnswerPassedFromConfig() {
        var config = Config()
        config.enginesTavily.includeAnswer = true
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(backend.includeAnswer == true)
    }

    @Test func emptyAPIKeyYieldsUnavailableBackend() {
        var config = Config()
        config.enginesTavily.apiKey = ""
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(!backend.isAvailable)
    }

    @Test func nonEmptyAPIKeyYieldsAvailableBackend() {
        var config = Config()
        config.enginesTavily.apiKey = "some-key"
        let backend = TavilyBackend.makeTavily(from: config)
        #expect(backend.isAvailable)
    }

    @Test func injectedTransportIsUsed() {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let config = Config()
        let backend = TavilyBackend.makeTavily(from: config, transport: transport)
        #expect(backend.transport.session === transport.session)
    }
}
