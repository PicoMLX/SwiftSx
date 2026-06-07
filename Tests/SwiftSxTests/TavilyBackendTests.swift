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

    @Test func bodySiteUsesIncludeDomainsWhenNonEmpty() throws {
        let options = SearchOptions(query: "swift", site: "github.com")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        // query must NOT have a "site:" prefix — domain filtering via include_domains
        #expect(dict["query"] as? String == "swift")
        // include_domains must be ["github.com"]
        let domains = dict["include_domains"] as? [String]
        #expect(domains == ["github.com"])
    }

    @Test func bodySiteQueryHasNoSitePrefixWhenSiteSet() throws {
        let options = SearchOptions(query: "repos", site: "github.com")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        let q = dict["query"] as? String ?? ""
        #expect(!q.hasPrefix("site:"))
    }

    @Test func bodyIncludeDomainsAbsentWhenSiteEmpty() throws {
        let options = SearchOptions(query: "swift", site: "")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["query"] as? String == "swift")
        #expect(dict["include_domains"] == nil)
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

    // MARK: time_range

    @Test func bodyTimeRangePresentWhenSet() throws {
        let options = SearchOptions(query: "test", timeRange: "day")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "day")
    }

    @Test func bodyTimeRangeWeekPassedThrough() throws {
        let options = SearchOptions(query: "test", timeRange: "week")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "week")
    }

    @Test func bodyTimeRangeMonthPassedThrough() throws {
        let options = SearchOptions(query: "test", timeRange: "month")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "month")
    }

    @Test func bodyTimeRangeYearPassedThrough() throws {
        let options = SearchOptions(query: "test", timeRange: "year")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "year")
    }

    @Test func bodyTimeRangeShortDExpandsToDay() throws {
        let options = SearchOptions(query: "test", timeRange: "d")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "day")
    }

    @Test func bodyTimeRangeShortWExpandsToWeek() throws {
        let options = SearchOptions(query: "test", timeRange: "w")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "week")
    }

    @Test func bodyTimeRangeShortMExpandsToMonth() throws {
        let options = SearchOptions(query: "test", timeRange: "m")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "month")
    }

    @Test func bodyTimeRangeShortYExpandsToYear() throws {
        let options = SearchOptions(query: "test", timeRange: "y")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] as? String == "year")
    }

    @Test func bodyTimeRangeAbsentWhenEmpty() throws {
        let options = SearchOptions(query: "test", timeRange: "")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["time_range"] == nil)
    }

    // MARK: topic (categories → topic)

    @Test func bodyTopicIsNewsWhenCategoriesContainsNews() throws {
        let options = SearchOptions(query: "test", categories: ["news"])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] as? String == "news")
    }

    @Test func bodyTopicIsFinanceWhenCategoriesContainsFinance() throws {
        let options = SearchOptions(query: "test", categories: ["finance"])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] as? String == "finance")
    }

    @Test func bodyTopicNewsPreferredOverFinance() throws {
        let options = SearchOptions(query: "test", categories: ["news", "finance"])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] as? String == "news")
    }

    @Test func bodyTopicAbsentWhenCategoriesEmpty() throws {
        let options = SearchOptions(query: "test", categories: [])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] == nil)
    }

    @Test func bodyTopicAbsentWhenCategoriesContainsGeneral() throws {
        let options = SearchOptions(query: "test", categories: ["general"])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] == nil)
    }

    @Test func bodyTopicAbsentWhenCategoriesContainsOther() throws {
        let options = SearchOptions(query: "test", categories: ["science", "technology"])
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["topic"] == nil)
    }

    // MARK: safe_search

    @Test func bodySafeSearchSentWithConfiguredLevel() throws {
        let options = SearchOptions(query: "test", safeSearch: "strict")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["safe_search"] as? String == "strict")
    }

    @Test func bodySafeSearchReflectsOffLevel() throws {
        let options = SearchOptions(query: "test", safeSearch: "off")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["safe_search"] as? String == "off")
    }

    @Test func bodySafeSearchAbsentWhenLevelEmpty() throws {
        let options = SearchOptions(query: "test", safeSearch: "")
        let (_, body) = try backend.makeRequest(options)
        let dict = decodeTavilyBody(body)
        #expect(dict["safe_search"] == nil)
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

    @Test func status400ThrowsInvalidResponseNotNetwork() async throws {
        // A 400 is a bad-request (usage) error, not network — it must map to the
        // transient class (exit 1), never fail-closed (exit 7).
        let backend = makeBackend()
        setHandler(status: 400, body: Data("Bad Request".utf8))

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
            #expect(error.code.sxExitCode == .general)
            #expect(error.message.contains("400"))
        }
    }

    @Test func status432ThrowsRateLimitNotNetwork() async throws {
        let backend = makeBackend()
        setHandler(status: 432, body: Data("Plan limit".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .rateLimit)
            #expect(error.code.sxExitCode == .general)
            #expect(error.message.contains("432"))
        }
    }

    @Test func status433ThrowsRateLimitNotNetwork() async throws {
        let backend = makeBackend()
        setHandler(status: 433, body: Data("Out of credits".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .rateLimit)
            #expect(error.code.sxExitCode == .general)
            #expect(error.message.contains("433"))
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

    // MARK: Pagination short-circuit

    @Test func pageNoTwoThrowsWithoutHittingNetwork() async throws {
        // Tavily has no pagination; page > 1 must throw a BackendError without any
        // network request. We install a handler that would fail the test if invoked.
        let backend = makeBackend()
        MockURLProtocol.handler = { _ in
            Issue.record("Tavily backend should not make a network request for pageNo > 1")
            return (HTTPURLResponse(url: URL(string: "https://api.tavily.com/search")!,
                                   statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: [:])!,
                    Data())
        }

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test", pageNo: 2))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test", pageNo: 2))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test func pageNoHighThrows() async throws {
        // Any pageNo > 1 should throw a BackendError immediately.
        let backend = makeBackend()
        MockURLProtocol.handler = { _ in
            Issue.record("Tavily backend should not make a network request for pageNo > 1")
            return (HTTPURLResponse(url: URL(string: "https://api.tavily.com/search")!,
                                   statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: [:])!,
                    Data())
        }

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test", pageNo: 10))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test", pageNo: 10))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test func pageNoOneStillHitsNetwork() async throws {
        // pageNo=1 (the default) must NOT be short-circuited.
        let backend = makeBackend()
        let body = tavilyJSON(results: [
            tavilyItem(title: "Page1Result", url: "https://example.com"),
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test", pageNo: 1))
        #expect(results.count == 1)
        #expect(results[0].title == "Page1Result")
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
