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
private func parseQuery(_ urlString: String) -> [String: String] {
    guard let components = URLComponents(string: urlString) else { return [:] }
    var dict = [String: String]()
    for item in components.queryItems ?? [] {
        dict[item.name] = item.value ?? ""
    }
    return dict
}

/// Decode a `application/x-www-form-urlencoded` body into a [key: value] dictionary.
private func parseFormBody(_ data: Data) -> [String: String] {
    guard let string = String(data: data, encoding: .utf8) else { return [:] }
    var dict = [String: String]()
    for pair in string.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key   = String(parts[0]).replacingOccurrences(of: "+", with: " ")
                        .removingPercentEncoding ?? String(parts[0])
        let value = String(parts[1]).replacingOccurrences(of: "+", with: " ")
                        .removingPercentEncoding ?? String(parts[1])
        dict[key] = value
    }
    return dict
}

/// Build a minimal valid SearXNG JSON response body.
private func searxngJSON(results: [[String: String]] = []) -> Data {
    let entries = results.map { dict in
        let fields = dict.map { k, v in "\"\(k)\": \"\(v)\"" }.joined(separator: ", ")
        return "{\(fields)}"
    }
    let body = "{\"results\": [\(entries.joined(separator: ", "))]}"
    return Data(body.utf8)
}

// MARK: - makeRequest: GET params

@Suite struct SearxngMakeRequestGETTests {

    private let backend = SearxngBackend(baseURL: "https://searx.example.com", httpMethod: "GET")

    @Test func getMethodIsUsed() throws {
        let (req, body) = try backend.makeRequest(SearchOptions(query: "swift"))
        #expect(req.method == .get)
        #expect(body == nil)
    }

    @Test func queryParamPresent() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "swift concurrency"))
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "swift concurrency")
    }

    @Test func formatIsAlwaysJSON() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["format"] == "json")
    }

    @Test func sitePrefixAddedWhenNonEmpty() throws {
        let options = SearchOptions(query: "swift", site: "github.com")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "site:github.com swift")
    }

    @Test func sitePrefixOmittedWhenEmpty() throws {
        let options = SearchOptions(query: "swift", site: "")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["q"] == "swift")
    }

    @Test func categoriesJoinedWithComma() throws {
        let options = SearchOptions(query: "test", categories: ["general", "news"])
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["categories"] == "general,news")
    }

    @Test func categoriesOmittedWhenEmpty() throws {
        let options = SearchOptions(query: "test", categories: [])
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["categories"] == nil)
    }

    @Test func enginesJoinedWithComma() throws {
        let options = SearchOptions(query: "test", engines: ["google", "bing"])
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["engines"] == "google,bing")
    }

    @Test func enginesOmittedWhenEmpty() throws {
        let options = SearchOptions(query: "test", engines: [])
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["engines"] == nil)
    }

    @Test func safesearchNoneMapsToZero() throws {
        let options = SearchOptions(query: "test", safeSearch: "none")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "0")
    }

    @Test func safesearchModerateMapsToOne() throws {
        let options = SearchOptions(query: "test", safeSearch: "moderate")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "1")
    }

    @Test func safesearchStrictMapsToTwo() throws {
        let options = SearchOptions(query: "test", safeSearch: "strict")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "2")
    }

    @Test func safesearchUnknownPassedThrough() throws {
        let options = SearchOptions(query: "test", safeSearch: "custom")
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["safesearch"] == "custom")
    }

    @Test func pagenoOmittedWhenOne() throws {
        let options = SearchOptions(query: "test", pageNo: 1)
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["pageno"] == nil)
    }

    @Test func pagenoIncludedWhenGreaterThanOne() throws {
        let options = SearchOptions(query: "test", pageNo: 3)
        let (req, _) = try backend.makeRequest(options)
        let params = parseQuery(req.url?.absoluteString ?? "")
        #expect(params["pageno"] == "3")
    }

    @Test func trailingSlashTrimmedFromBaseURL() throws {
        let b = SearxngBackend(baseURL: "https://searx.example.com/", httpMethod: "GET")
        let (req, _) = try b.makeRequest(SearchOptions(query: "test"))
        let urlStr = req.url?.absoluteString ?? ""
        #expect(urlStr.hasPrefix("https://searx.example.com/search"))
        // Must not contain a double-slash segment like "//search"
        #expect(!urlStr.contains("//search"))
    }

    @Test func endpointPathIsSearch() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.url?.path == "/search")
    }
}

// MARK: - makeRequest: POST params

@Suite struct SearxngMakeRequestPOSTTests {

    private let backend = SearxngBackend(baseURL: "https://searx.example.com", httpMethod: "POST")

    @Test func postMethodIsUsed() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.method == .post)
    }

    @Test func bodyIsNonNilForPost() throws {
        let (_, body) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(body != nil)
    }

    @Test func postBodyContainsQuery() throws {
        let (_, body) = try backend.makeRequest(SearchOptions(query: "swift concurrency"))
        let params = parseFormBody(body!)
        #expect(params["q"] == "swift concurrency")
    }

    @Test func postBodyContainsFormatJSON() throws {
        let (_, body) = try backend.makeRequest(SearchOptions(query: "test"))
        let params = parseFormBody(body!)
        #expect(params["format"] == "json")
    }

    @Test func postBodyCategoriesJoined() throws {
        let options = SearchOptions(query: "test", categories: ["general", "news"])
        let (_, body) = try backend.makeRequest(options)
        let params = parseFormBody(body!)
        #expect(params["categories"] == "general,news")
    }

    @Test func postBodyEnginesJoined() throws {
        let options = SearchOptions(query: "test", engines: ["google", "bing"])
        let (_, body) = try backend.makeRequest(options)
        let params = parseFormBody(body!)
        #expect(params["engines"] == "google,bing")
    }

    @Test func postBodySafesearchMapping() throws {
        let options = SearchOptions(query: "test", safeSearch: "none")
        let (_, body) = try backend.makeRequest(options)
        let params = parseFormBody(body!)
        #expect(params["safesearch"] == "0")
    }

    @Test func postBodyPagenoOmittedWhenOne() throws {
        let options = SearchOptions(query: "test", pageNo: 1)
        let (_, body) = try backend.makeRequest(options)
        let params = parseFormBody(body!)
        #expect(params["pageno"] == nil)
    }

    @Test func postBodyPagenoIncludedWhenGreaterThanOne() throws {
        let options = SearchOptions(query: "test", pageNo: 2)
        let (_, body) = try backend.makeRequest(options)
        let params = parseFormBody(body!)
        #expect(params["pageno"] == "2")
    }

    @Test func postHasFormContentTypeHeader() throws {
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.contentType] == "application/x-www-form-urlencoded")
    }

    @Test func getDoesNotHaveFormContentTypeHeader() throws {
        let getBackend = SearxngBackend(baseURL: "https://searx.example.com", httpMethod: "GET")
        let (req, _) = try getBackend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.contentType] == nil)
    }
}

// MARK: - makeRequest: headers

@Suite struct SearxngMakeRequestHeaderTests {

    @Test func acceptHeaderIsApplicationJSON() throws {
        let backend = SearxngBackend(baseURL: "https://searx.example.com")
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.accept] == "application/json")
    }

    @Test func acceptEncodingPresent() throws {
        let backend = SearxngBackend(baseURL: "https://searx.example.com")
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        let acceptEncoding = req.headerFields[HTTPField.Name("Accept-Encoding")!]
        #expect(acceptEncoding == "gzip, deflate")
    }

    @Test func userAgentPresentByDefault() throws {
        let backend = SearxngBackend(baseURL: "https://searx.example.com", noUserAgent: false)
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.userAgent] == "sx/2.0")
    }

    @Test func userAgentOmittedWhenNoUserAgentTrue() throws {
        let backend = SearxngBackend(baseURL: "https://searx.example.com", noUserAgent: true)
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.userAgent] == nil)
    }

    @Test func basicAuthPresentWhenBothCredsSet() throws {
        let backend = SearxngBackend(
            baseURL: "https://searx.example.com",
            username: "alice",
            password: "s3cret"
        )
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        let auth = req.headerFields[.authorization]
        // "alice:s3cret" base64 is "YWxpY2U6czNjcmV0"
        let expectedCredential = Data("alice:s3cret".utf8).base64EncodedString()
        #expect(auth == "Basic \(expectedCredential)")
    }

    @Test func basicAuthAbsentWhenUsernameEmpty() throws {
        let backend = SearxngBackend(
            baseURL: "https://searx.example.com",
            username: "",
            password: "s3cret"
        )
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == nil)
    }

    @Test func basicAuthAbsentWhenPasswordEmpty() throws {
        let backend = SearxngBackend(
            baseURL: "https://searx.example.com",
            username: "alice",
            password: ""
        )
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == nil)
    }

    @Test func basicAuthAbsentWhenBothCredsEmpty() throws {
        let backend = SearxngBackend(
            baseURL: "https://searx.example.com",
            username: "",
            password: ""
        )
        let (req, _) = try backend.makeRequest(SearchOptions(query: "test"))
        #expect(req.headerFields[.authorization] == nil)
    }
}

// MARK: - isAvailable

@Suite struct SearxngIsAvailableTests {

    @Test func trueForValidHTTPSURL() {
        let backend = SearxngBackend(baseURL: "https://searx.example.com")
        #expect(backend.isAvailable)
    }

    @Test func trueForValidHTTPURL() {
        let backend = SearxngBackend(baseURL: "http://localhost:8080")
        #expect(backend.isAvailable)
    }

    @Test func falseForEmptyBaseURL() {
        let backend = SearxngBackend(baseURL: "")
        #expect(!backend.isAvailable)
    }

    @Test func falseForURLWithNoScheme() {
        let backend = SearxngBackend(baseURL: "searx.example.com")
        #expect(!backend.isAvailable)
    }

    @Test func falseForGarbageURL() {
        let backend = SearxngBackend(baseURL: "not a url at all !!!")
        #expect(!backend.isAvailable)
    }
}

// MARK: - search: happy path + status codes

@Suite(.serialized)
struct SearxngSearchTests {

    private func makeBackend(
        httpMethod: String = "GET",
        noUserAgent: Bool = false,
        username: String = "",
        password: String = ""
    ) -> SearxngBackend {
        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        return SearxngBackend(
            baseURL: "https://searx.example.com",
            httpMethod: httpMethod,
            username: username,
            password: password,
            noUserAgent: noUserAgent,
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
        let body = searxngJSON(results: [
            ["title": "Swift.org", "url": "https://swift.org", "content": "Swift language home"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "swift"))
        #expect(results.count == 1)
        #expect(results[0].title == "Swift.org")
        #expect(results[0].url == "https://swift.org")
    }

    @Test func happyPathEmptyResultsArray() async throws {
        let backend = makeBackend()
        setHandler(status: 200, body: searxngJSON(results: []))

        let results = try await backend.search(SearchOptions(query: "xyzzy"))
        #expect(results.isEmpty)
    }

    @Test func happyPathMultipleResults() async throws {
        let backend = makeBackend()
        let body = searxngJSON(results: [
            ["title": "Alpha", "url": "https://a.example.com"],
            ["title": "Beta",  "url": "https://b.example.com"],
        ])
        setHandler(status: 200, body: body)

        let results = try await backend.search(SearchOptions(query: "test"))
        #expect(results.count == 2)
        #expect(results[0].title == "Alpha")
        #expect(results[1].title == "Beta")
    }

    // MARK: 2xx besides 200

    @Test func status201AlsoDecodes() async throws {
        let backend = makeBackend()
        setHandler(status: 201, body: searxngJSON())
        // 201 is in 200...299; should not throw.
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
            // A 403 most often means JSON output is disabled — say so.
            #expect(error.message.contains("JSON"))
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

    @Test func validJSONButWrongShapeThrowsInvalidResponse() async throws {
        let backend = makeBackend()
        // Valid JSON but missing "results" key.
        setHandler(status: 200, body: Data("{\"hits\": []}".utf8))

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .invalidResponse)
        }
    }

    // MARK: Unavailable backend throws

    @Test func unavailableBackendThrowsWithoutNetwork() async throws {
        let backend = SearxngBackend(baseURL: "")
        await #expect(throws: BackendError.self) {
            _ = try await backend.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await backend.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .unavailable)
            #expect(error.message.contains("searxng_url"))
        }
    }
}

// MARK: - MultiSearxngBackend: ordered strategy

@Suite(.serialized)
struct MultiSearxngOrderedTests {

    @Test func firstAvailableInstanceSucceeds() async throws {
        let jsonBody = searxngJSON(results: [["title": "First", "url": "https://first.example.com"]])

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://a.example.com/search")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jsonBody)
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instance = SearxngBackend(
            baseURL: "https://a.example.com",
            transport: transport
        )
        let multi = MultiSearxngBackend(instances: [instance], strategy: "ordered")
        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].title == "First")
    }

    @Test func orderedFirstFailsSecondSucceeds() async throws {
        // Instance A will return 500, instance B will return 200.
        MockURLProtocol.handler = { request in
            let host = request.url?.host ?? ""
            if host == "a.example.com" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: [:]
                )!
                return (response, Data())
            } else {
                let body = searxngJSON(results: [["title": "From B", "url": "https://b.example.com"]])
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, body)
            }
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instanceA = SearxngBackend(baseURL: "https://a.example.com", transport: transport)
        let instanceB = SearxngBackend(baseURL: "https://b.example.com", transport: transport)
        let multi = MultiSearxngBackend(instances: [instanceA, instanceB], strategy: "ordered")

        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].title == "From B")
    }

    @Test func orderedAllFailThrowsNetworkError() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (response, Data())
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instanceA = SearxngBackend(baseURL: "https://a.example.com", transport: transport)
        let instanceB = SearxngBackend(baseURL: "https://b.example.com", transport: transport)
        let multi = MultiSearxngBackend(instances: [instanceA, instanceB], strategy: "ordered")

        await #expect(throws: BackendError.self) {
            _ = try await multi.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await multi.search(SearchOptions(query: "test"))
        } catch let error as BackendError {
            #expect(error.code == .network)
            #expect(error.message.contains("all searxng instances failed"))
        }
    }

    @Test func orderedSkipsUnavailableInstance() async throws {
        MockURLProtocol.handler = { request in
            let body = searxngJSON(results: [["title": "OK", "url": "https://b.example.com"]])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        // instanceA has an empty URL → not available.
        let instanceA = SearxngBackend(baseURL: "", transport: transport)
        let instanceB = SearxngBackend(baseURL: "https://b.example.com", transport: transport)
        let multi = MultiSearxngBackend(instances: [instanceA, instanceB], strategy: "ordered")

        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].title == "OK")
    }

    @Test func noAvailableInstancesThrows() async throws {
        let multi = MultiSearxngBackend(instances: [], strategy: "ordered")
        await #expect(throws: BackendError.self) {
            _ = try await multi.search(SearchOptions(query: "test"))
        }
    }

    @Test func isAvailableTrueWhenAtLeastOneInstanceAvailable() {
        let a = SearxngBackend(baseURL: "")
        let b = SearxngBackend(baseURL: "https://searx.example.com")
        let multi = MultiSearxngBackend(instances: [a, b], strategy: "ordered")
        #expect(multi.isAvailable)
    }

    @Test func isAvailableFalseWhenNoInstancesAvailable() {
        let a = SearxngBackend(baseURL: "")
        let b = SearxngBackend(baseURL: "")
        let multi = MultiSearxngBackend(instances: [a, b], strategy: "ordered")
        #expect(!multi.isAvailable)
    }

    @Test func isAvailableFalseWhenInstancesEmpty() {
        let multi = MultiSearxngBackend(instances: [], strategy: "ordered")
        #expect(!multi.isAvailable)
    }

    @Test func unknownStrategyBehavesLikeOrdered() async throws {
        MockURLProtocol.handler = { request in
            let body = searxngJSON(results: [["title": "Result", "url": "https://x.example.com"]])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instance = SearxngBackend(baseURL: "https://x.example.com", transport: transport)
        let multi = MultiSearxngBackend(instances: [instance], strategy: "round-robin")

        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
    }
}

// MARK: - MultiSearxngBackend: parallel-fastest strategy

@Suite(.serialized)
struct MultiSearxngParallelFastestTests {

    @Test func parallelFastestReturnsFirstSuccess() async throws {
        MockURLProtocol.handler = { request in
            let body = searxngJSON(results: [["title": "Parallel", "url": "https://p.example.com"]])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instanceA = SearxngBackend(baseURL: "https://a.example.com", transport: transport)
        let instanceB = SearxngBackend(baseURL: "https://b.example.com", transport: transport)
        let multi = MultiSearxngBackend(
            instances: [instanceA, instanceB],
            strategy: "parallel-fastest"
        )

        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
    }

    @Test func parallelFastestNoInstancesThrows() async throws {
        let multi = MultiSearxngBackend(instances: [], strategy: "parallel-fastest")
        await #expect(throws: BackendError.self) {
            _ = try await multi.search(SearchOptions(query: "test"))
        }
    }

    @Test func fastestAliasRacesLikeParallelFastest() async throws {
        // "fastest" is accepted as an alias for "parallel-fastest" rather than
        // silently falling through to "ordered".
        MockURLProtocol.handler = { request in
            let body = searxngJSON(results: [["title": "Fastest", "url": "https://p.example.com"]])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let session = MockURLProtocol.session()
        let transport = HTTPTransport(session: session)
        let instanceA = SearxngBackend(baseURL: "https://a.example.com", transport: transport)
        let instanceB = SearxngBackend(baseURL: "https://b.example.com", transport: transport)
        let multi = MultiSearxngBackend(instances: [instanceA, instanceB], strategy: "fastest")

        let results = try await multi.search(SearchOptions(query: "test"))
        #expect(results.count == 1)
        #expect(results[0].title == "Fastest")
    }
}

// MARK: - Factory: SearxngBackend.makeBackend(from:transport:)

@Suite struct SearxngFactoryTests {

    @Test func singleURLBuildsMultiBackendWithOneInstance() throws {
        var config = Config()
        config.searxngURL  = "https://searx.example.com"
        config.searxngURLs = []
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances.count == 1)
        #expect(m.instances[0].baseURL == "https://searx.example.com")
    }

    @Test func multipleURLsWinOverSingleURL() throws {
        var config = Config()
        config.searxngURL  = "https://single.example.com"
        config.searxngURLs = ["https://a.example.com", "https://b.example.com"]
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances.count == 2)
        #expect(m.instances[0].baseURL == "https://a.example.com")
        #expect(m.instances[1].baseURL == "https://b.example.com")
    }

    @Test func emptyURLsBuildsMultiBackendWithZeroInstances() throws {
        var config = Config()
        config.searxngURL  = ""
        config.searxngURLs = []
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances.isEmpty)
    }

    @Test func strategyPassedThrough() throws {
        var config = Config()
        config.searxngURL      = "https://searx.example.com"
        config.searxngURLs     = []
        config.searxngStrategy = "parallel-fastest"
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.strategy == "parallel-fastest")
    }

    @Test func credentialsPassedToInstances() throws {
        var config = Config()
        config.searxngURL      = "https://searx.example.com"
        config.searxngURLs     = []
        config.searxngUsername = "bob"
        config.searxngPassword = "hunter2"
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances[0].username == "bob")
        #expect(m.instances[0].password == "hunter2")
    }

    @Test func noUserAgentPassedToInstances() throws {
        var config = Config()
        config.searxngURL   = "https://searx.example.com"
        config.searxngURLs  = []
        config.noUserAgent  = true
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances[0].noUserAgent == true)
    }

    @Test func httpMethodPassedToInstances() throws {
        var config = Config()
        config.searxngURL  = "https://searx.example.com"
        config.searxngURLs = []
        config.httpMethod  = "POST"
        let backend = SearxngBackend.makeBackend(from: config)
        let m = try #require(backend as? MultiSearxngBackend)
        #expect(m.instances[0].httpMethod == "POST")
    }
}
