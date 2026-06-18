import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftSx

// MARK: - Helpers

/// Parse a percent-encoded query string into a [key: value] dictionary.
private func parseBraveQuery(_ urlString: String) -> [String: String] {
    guard let components = URLComponents(string: urlString) else { return [:] }
    var dict = [String: String]()
    for item in components.queryItems ?? [] {
        dict[item.name] = item.value ?? ""
    }
    return dict
}

/// Build a minimal valid Brave Search JSON response body.
private func braveJSON(results: [[String: String]] = []) -> Data {
    let entries = results.map { dict in
        let fields = dict.map { k, v in "\"\(k)\": \"\(v)\"" }.joined(separator: ", ")
        return "{\(fields)}"
    }
    let body = "{\"web\": {\"results\": [\(entries.joined(separator: ", "))]}}"
    return Data(body.utf8)
}

// MARK: - makeRequest: query params

@Suite struct BraveMakeRequestQueryTests {

    private let backend = BraveBackend(apiKey: "test-key")

    @Test func getMethodIsUsed() throws {
        let req = try backend.makeRequest(SearchOptions(query: "swift"))
        #expect(req.method == .get)
    }

    @Test func queryParamPresent() throws {
        let req = try backend.makeRequest(SearchOptions(query: "swift concurrency"))
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "swift concurrency")
    }

    @Test func sitePrefixAddedWhenNonEmpty() throws {
        let options = SearchOptions(query: "swift", site: "github.com")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "site:github.com swift")
    }

    @Test func sitePrefixOmittedWhenEmpty() throws {
        let options = SearchOptions(query: "swift", site: "")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "swift")
    }

    @Test func countDefaultsToTenWhenZero() throws {
        let options = SearchOptions(query: "test", numResults: 0)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "10")
    }

    @Test func countDefaultsToTenWhenNegative() throws {
        let options = SearchOptions(query: "test", numResults: -5)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "10")
    }

    @Test func countClampsToTwentyWhenExceeds() throws {
        let options = SearchOptions(query: "test", numResults: 25)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "20")
    }

    @Test func countPassedThroughWhenInRange() throws {
        let options = SearchOptions(query: "test", numResults: 5)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "5")
    }

    @Test func countAtUpperBoundAllowed() throws {
        let options = SearchOptions(query: "test", numResults: 20)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "20")
    }

    @Test func countAtLowerBoundAllowed() throws {
        let options = SearchOptions(query: "test", numResults: 1)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["count"] == "1")
    }

    @Test func offsetOmittedWhenPageNoOne() throws {
        let options = SearchOptions(query: "test", pageNo: 1)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == nil)
    }

    @Test func offsetCalculatedWhenPageNoGreaterThanOne() throws {
        // pageNo=2 → offset=1 (zero-based page index, not result offset)
        let options = SearchOptions(query: "test", pageNo: 2, numResults: 10)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == "1")
    }

    @Test func offsetPageThreeIsTwo() throws {
        // pageNo=3 → offset=2 (independent of count)
        let options = SearchOptions(query: "test", pageNo: 3, numResults: 0)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == "2")
    }

    @Test func offsetPageFourIsThree() throws {
        // pageNo=4 → offset=3 (count does not affect offset)
        let options = SearchOptions(query: "test", pageNo: 4, numResults: 5)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == "3")
    }

    @Test func offsetClampsToNineWhenPageNoExceedsTen() throws {
        // pageNo=15 → raw offset would be 14, but Brave's max is 9
        let options = SearchOptions(query: "test", pageNo: 15)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == "9")
    }

    @Test func offsetAtMaxBoundaryIsNine() throws {
        // pageNo=10 → raw offset=9 (exactly at the cap)
        let options = SearchOptions(query: "test", pageNo: 10)
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["offset"] == "9")
    }

    @Test func safesearchOffMapsToOff() throws {
        let options = SearchOptions(query: "test", safeSearch: "off")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "off")
    }

    @Test func safesearchNoneMapsToOff() throws {
        let options = SearchOptions(query: "test", safeSearch: "none")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "off")
    }

    @Test func safesearchStrictMapsToStrict() throws {
        let options = SearchOptions(query: "test", safeSearch: "strict")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "strict")
    }

    @Test func safesearchModerateMapToModerate() throws {
        let options = SearchOptions(query: "test", safeSearch: "moderate")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "moderate")
    }

    @Test func safesearchUnknownMapsToModerate() throws {
        let options = SearchOptions(query: "test", safeSearch: "custom")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "moderate")
    }

    // MARK: search_lang / ui_lang

    @Test func searchLangSplitsLocaleToLangCode() throws {
        // "en-US" → search_lang="en" (bare language code)
        let options = SearchOptions(query: "test", language: "en-US")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["search_lang"] == "en")
    }

    @Test func uiLangSetToFullLocaleWhenDashPresent() throws {
        // "en-US" → ui_lang="en-US" (the original locale)
        let options = SearchOptions(query: "test", language: "en-US")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["ui_lang"] == "en-US")
    }

    @Test func searchLangAbsentWhenLanguageEmpty() throws {
        let options = SearchOptions(query: "test", language: "")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["search_lang"] == nil)
    }

    @Test func uiLangAbsentWhenLanguageEmpty() throws {
        let options = SearchOptions(query: "test", language: "")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["ui_lang"] == nil)
    }

    @Test func searchLangNoDashSentAsIs() throws {
        // "en" (no dash) → search_lang="en", no ui_lang
        let options = SearchOptions(query: "test", language: "en")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["search_lang"] == "en")
        #expect(params["ui_lang"] == nil)
    }

    @Test func searchLangDeLocaleSplits() throws {
        // "de-DE" → search_lang="de", ui_lang="de-DE"
        let options = SearchOptions(query: "test", language: "de-DE")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["search_lang"] == "de")
        #expect(params["ui_lang"] == "de-DE")
    }

    // MARK: freshness (time_range → freshness)

    @Test func freshnessDayMapsToProductDay() throws {
        let options = SearchOptions(query: "test", timeRange: "day")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pd")
    }

    @Test func freshnessWeekMapsToProductWeek() throws {
        let options = SearchOptions(query: "test", timeRange: "week")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pw")
    }

    @Test func freshnessMonthMapsToProductMonth() throws {
        let options = SearchOptions(query: "test", timeRange: "month")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pm")
    }

    @Test func freshnessYearMapsToProductYear() throws {
        let options = SearchOptions(query: "test", timeRange: "year")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "py")
    }

    @Test func freshnessShortFormDMapsToProductDay() throws {
        let options = SearchOptions(query: "test", timeRange: "d")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pd")
    }

    @Test func freshnessShortFormWMapsToProductWeek() throws {
        let options = SearchOptions(query: "test", timeRange: "w")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pw")
    }

    @Test func freshnessShortFormMMapsToProductMonth() throws {
        let options = SearchOptions(query: "test", timeRange: "m")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "pm")
    }

    @Test func freshnessShortFormYMapsToProductYear() throws {
        let options = SearchOptions(query: "test", timeRange: "y")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == "py")
    }

    @Test func freshnessAbsentWhenTimeRangeEmpty() throws {
        let options = SearchOptions(query: "test", timeRange: "")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == nil)
    }

    @Test func freshnessAbsentWhenTimeRangeUnknown() throws {
        let options = SearchOptions(query: "test", timeRange: "yesterday")
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["freshness"] == nil)
    }

    // MARK: result_filter (categories → result_filter)

    @Test func resultFilterFromNewsCategory() throws {
        let options = SearchOptions(query: "test", categories: ["news"])
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["result_filter"] == "news")
    }

    @Test func resultFilterFromVideosCategory() throws {
        let options = SearchOptions(query: "test", categories: ["videos"])
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["result_filter"] == "videos")
    }

    @Test func resultFilterCombinesCategoriesPreservingOrder() throws {
        let options = SearchOptions(query: "test", categories: ["news", "videos"])
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["result_filter"] == "news,videos")
    }

    @Test func resultFilterAbsentWhenCategoriesEmpty() throws {
        let options = SearchOptions(query: "test", categories: [])
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["result_filter"] == nil)
    }

    @Test func resultFilterOmitsUnknownCategories() throws {
        let options = SearchOptions(query: "test", categories: ["science"])
        let req = try backend.makeRequest(options)
        let params = parseBraveQuery(req.url?.absoluteString ?? "")
        #expect(params["result_filter"] == nil)
    }

    // MARK: endpoint

    @Test func endpointIsCorrect() throws {
        let req = try backend.makeRequest(SearchOptions(query: "test"))
        let urlStr = req.url?.absoluteString ?? ""
        #expect(urlStr.hasPrefix("https://api.search.brave.com/res/v1/web/search"))
    }
}

// MARK: - makeRequest: headers

@Suite struct BraveMakeRequestHeaderTests {

    @Test func acceptHeaderIsApplicationJSON() throws {
        let backend = BraveBackend(apiKey: "test-key")
        let req = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.accept] == "application/json")
    }

    @Test func xSubscriptionTokenContainsAPIKey() throws {
        let backend = BraveBackend(apiKey: "my-brave-api-key")
        let req = try backend.makeRequest(SearchOptions(query: "test"))
        let tokenField = HTTPField.Name("X-Subscription-Token")!
        #expect(req.headerFields[tokenField] == "my-brave-api-key")
    }
}

// MARK: - isAvailable

@Suite struct BraveIsAvailableTests {

    @Test func trueWhenAPIKeyNonEmpty() {
        let backend = BraveBackend(apiKey: "some-key")
        #expect(backend.isAvailable)
    }

    @Test func falseWhenAPIKeyEmpty() {
        let backend = BraveBackend(apiKey: "")
        #expect(!backend.isAvailable)
    }
}

// MARK: - search: happy path + status codes

@Suite(.serialized)
struct BraveSearchTests {

    private func makeBackend(apiKey: String = "test-key") -> BraveBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return BraveBackend(apiKey: apiKey, transport: transport)
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
        let body = braveJSON(results: [
            ["title": "Swift.org", "url": "https://swift.org", "description": "Swift language home"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
        #expect(results[0].content == "Swift language home")
        #expect(results[0].engine == "brave")
        #expect(results[0].engines == ["brave"])
    }

    @Test func happyPathEmptyResultsArray() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: braveJSON(results: []))

        let results = try await backend.search(SearchOptions(query: "xyzzy"))
        #expect(results.isEmpty)
    }

    @Test func happyPathMultipleResults() async throws {
        let backend = makeBackend()
        let body = braveJSON(results: [
            ["title": "Alpha", "url": "https://a.example.com"],
            ["title": "Beta",  "url": "https://b.example.com"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 2)
        #expect(results[0].title == "Alpha")
        #expect(results[1].title == "Beta")
    }

    @Test func missingWebKeyYieldsEmptyResults() async throws {
        let backend = makeBackend()
        // Valid JSON but no "web" key → empty results, no throw.
        setHandler(status: 200, body: Data("{}".utf8))

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.isEmpty)
    }

    @Test func decodesNewsAndVideosSections() async throws {
        let backend = makeBackend()
        // Brave returns separate web/news/videos sections; all should be merged
        // (web, then news, then videos), preserving order.
        let body = Data("""
        {
          "web":    {"results": [{"title": "W", "url": "https://w.com", "description": "web"}]},
          "news":   {"results": [{"title": "N", "url": "https://n.com", "description": "news"}]},
          "videos": {"results": [{"title": "V", "url": "https://v.com", "description": "vid"}]}
        }
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 3)
        #expect(results.map(\.title) == ["W", "N", "V"])
    }

    @Test func capsMergedSectionsToRequestedCount() async throws {
        // Brave's `count` only limits the web section, so the merged
        // web+news+videos list must be capped to the requested count. With
        // --count 2 the result is [W, N], not all three sections.
        let backend = makeBackend()
        let body = Data("""
        {
          "web":    {"results": [{"title": "W", "url": "https://w.com", "description": "web"}]},
          "news":   {"results": [{"title": "N", "url": "https://n.com", "description": "news"}]},
          "videos": {"results": [{"title": "V", "url": "https://v.com", "description": "vid"}]}
        }
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test", numResults: 2))
        #expect(results.count == 2)
        #expect(results.map(\.title) == ["W", "N"])
    }

    @Test func mixedRankingOrdersResults() async throws {
        let backend = makeBackend()
        // Brave's `mixed.main` dictates the cross-section display order. Here it
        // interleaves web[1], all news, then web[0] — which is NOT the plain
        // web→news→videos concatenation ([W0, W1, N0]).
        let body = Data("""
        {
          "mixed": {"main": [
            {"type": "web", "index": 1},
            {"type": "news", "all": true},
            {"type": "web", "index": 0}
          ]},
          "web":  {"results": [
            {"title": "W0", "url": "https://w0.com", "description": "web0"},
            {"title": "W1", "url": "https://w1.com", "description": "web1"}
          ]},
          "news": {"results": [
            {"title": "N0", "url": "https://n0.com", "description": "news0"}
          ]}
        }
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.map(\.title) == ["W1", "N0", "W0"])
    }

    @Test func mixedRankingKeepsUnreferencedResults() async throws {
        let backend = makeBackend()
        // `mixed.main` references only web[0]; the unreferenced news result must
        // still be returned (appended), never silently dropped.
        let body = Data("""
        {
          "mixed": {"main": [{"type": "web", "index": 0}]},
          "web":  {"results": [{"title": "W0", "url": "https://w0.com", "description": "web0"}]},
          "news": {"results": [{"title": "N0", "url": "https://n0.com", "description": "news0"}]}
        }
        """.utf8)
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.map(\.title) == ["W0", "N0"])
    }

    @Test func status201AlsoDecodes() async throws {
        let backend = makeBackend()
        setHandler(status: 201, body: braveJSON())
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
            #expect(error.message.contains("BRAVE_API_KEY"))
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
        let backend = BraveBackend(apiKey: "")

        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .unavailable)
            #expect(error.message.contains("BRAVE_API_KEY"))
        }
    }
}

// MARK: - Factory: BraveBackend.makeBrave(from:transport:)

@Suite struct BraveFactoryTests {

    @Test func apiKeyPassedFromConfig() {
        var config = Config()
        config.enginesBrave.apiKey = "config-brave-key"
        let backend = BraveBackend.makeBrave(from: config)
        #expect(backend.apiKey == "config-brave-key")
    }

    @Test func emptyAPIKeyYieldsUnavailableBackend() {
        var config = Config()
        config.enginesBrave.apiKey = ""
        let backend = BraveBackend.makeBrave(from: config)
        #expect(!backend.isAvailable)
    }

    @Test func nonEmptyAPIKeyYieldsAvailableBackend() {
        var config = Config()
        config.enginesBrave.apiKey = "some-key"
        let backend = BraveBackend.makeBrave(from: config)
        #expect(backend.isAvailable)
    }

    @Test func injectedTransportIsUsed() {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let config = Config()
        let backend = BraveBackend.makeBrave(from: config, transport: transport)
        // Verify the transport was stored (indirectly via identity of session).
        #expect(backend.transport.session === transport.session)
    }
}
