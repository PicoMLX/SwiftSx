import Testing
import SwiftSx
@testable import SxCommand

/// Covers `shapedResults` — the URL filter + `--count` cap + `--first` ordering.
/// The key regression: a URL-less Tavily answer stub must not consume a `--count`
/// slot in URL-dependent modes (`--links`/`--html`/`--text`), where it is filtered
/// out anyway, or it would drop the last usable result and render empty output.
@Suite struct ResultShapingTests {

    private let answer = SearchResult(
        title: "Answer", url: "", content: "an answer",
        engine: "tavily", engines: ["tavily"], category: "answer")
    private let hit = SearchResult(
        title: "Hit", url: "https://example.com", content: "c",
        engine: "tavily", engines: ["tavily"])

    @Test func urlModeCapDoesNotLetAnswerStubDisplaceUsableResult() throws {
        // --links + --count 1 with an answer stub present: the URL-less answer is
        // filtered first, so the cap keeps the usable result rather than emptying out.
        let out = try Sx.parse(["--links", "q"])
            .shapedResults([answer, hit], needsURL: true, count: 1)
        #expect(out.count == 1)
        #expect(out[0].url == "https://example.com")
    }

    @Test func nonURLModeCapCountsAnswerTowardTotal() throws {
        // Plain/--json + --count 1: the answer is shown, so it takes the one slot —
        // the chosen "cap total to --count" behaviour.
        let out = try Sx.parse(["q"])
            .shapedResults([answer, hit], needsURL: false, count: 1)
        #expect(out.count == 1)
        #expect(out[0].category == "answer")
    }

    @Test func capTrimsToCountWhenAllResultsAreUsable() throws {
        let hits = (1...5).map { SearchResult(title: "H\($0)", url: "https://h\($0).com") }
        let out = try Sx.parse(["q"]).shapedResults(hits, needsURL: true, count: 3)
        #expect(out.count == 3)
        #expect(out.map(\.title) == ["H1", "H2", "H3"])
    }

    @Test func nonPositiveCountDisablesTheCap() throws {
        let out = try Sx.parse(["q"])
            .shapedResults([answer, hit], needsURL: false, count: 0)
        #expect(out.count == 2)
    }

    @Test func firstStillWinsAfterCap() throws {
        let out = try Sx.parse(["q", "--first"])
            .shapedResults([answer, hit], needsURL: true, count: 5)
        #expect(out.count == 1)
        #expect(out[0].url == "https://example.com")
    }
}
