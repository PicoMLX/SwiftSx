import Testing
import SwiftSx
@testable import SxCommand

@Suite struct FirstFlagTests {

    private let sample = [
        SearchResult(title: "A", url: "https://a.com"),
        SearchResult(title: "B", url: "https://b.com"),
        SearchResult(title: "C", url: "https://c.com"),
    ]

    @Test func parsesFirstFlag() throws {
        #expect(try Sx.parse(["q", "--first"]).first)
        #expect(!(try Sx.parse(["q"]).first))
    }

    @Test func firstKeepsOnlyTopResult() throws {
        let selected = try Sx.parse(["q", "--first"]).selectedResults(sample)
        #expect(selected.count == 1)
        #expect(selected.first?.title == "A")
    }

    @Test func withoutFirstKeepsAllResults() throws {
        #expect(try Sx.parse(["q"]).selectedResults(sample).count == 3)
    }

    @Test func firstOnEmptyResultsIsEmpty() throws {
        #expect(try Sx.parse(["q", "--first"]).selectedResults([]).isEmpty)
    }
}
