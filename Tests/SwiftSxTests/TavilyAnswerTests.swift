import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // HTTPURLResponse lives here on Linux
#endif
import Testing
@testable import SwiftSx

@Suite(.serialized, .mockURLProtocolSerialized)
struct TavilyAnswerTests {

    private func setHandler(status: Int, body: Data) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
    }

    private func backend(includeAnswer: Bool) -> TavilyBackend {
        TavilyBackend(
            apiKey: "test-key",
            includeAnswer: includeAnswer,
            transport: HTTPTransport(session: MockURLProtocol.session())
        )
    }

    @Test func answerSurfacedAsLeadingResultWhenRequested() async throws {
        let json = #"{"answer":"Swift is a language.","results":[{"title":"Swift.org","url":"https://swift.org","content":"home"}]}"#
        setHandler(status: 200, body: Data(json.utf8))

        let results = try await backend(includeAnswer: true).search(SearchOptions(query: "swift"))
        #expect(results.count == 2)
        #expect(results[0].category == "answer")
        #expect(results[0].content == "Swift is a language.")
        #expect(results[0].url.isEmpty)
        #expect(results[0].engine == "tavily")
        // The real results follow the answer.
        #expect(results[1].title == "Swift.org")
    }

    @Test func answerNotSurfacedWhenIncludeAnswerFalse() async throws {
        let json = #"{"answer":"Ignored.","results":[{"title":"R","url":"https://r.com","content":"c"}]}"#
        setHandler(status: 200, body: Data(json.utf8))

        let results = try await backend(includeAnswer: false).search(SearchOptions(query: "x"))
        #expect(results.count == 1)
        #expect(results[0].title == "R")
    }

    @Test func blankAnswerIsIgnored() async throws {
        let json = #"{"answer":"   ","results":[{"title":"R","url":"https://r.com","content":"c"}]}"#
        setHandler(status: 200, body: Data(json.utf8))

        let results = try await backend(includeAnswer: true).search(SearchOptions(query: "x"))
        #expect(results.count == 1) // whitespace-only answer is not prepended
    }

    @Test func missingAnswerIsIgnored() async throws {
        let json = #"{"results":[{"title":"R","url":"https://r.com","content":"c"}]}"#
        setHandler(status: 200, body: Data(json.utf8))

        let results = try await backend(includeAnswer: true).search(SearchOptions(query: "x"))
        #expect(results.count == 1)
    }
}
