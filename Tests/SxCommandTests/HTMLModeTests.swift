import Testing
import SwiftSx
@testable import SxCommand

@Suite struct HTMLModeTests {

    @Test func parsesHtmlFlag() throws {
        #expect(try Sx.parse(["q", "--html"]).html)
        #expect(!(try Sx.parse(["q"]).html))
    }

    @Test func renderPagesFormatsTitledBlocks() {
        let results = [
            SearchResult(title: "Alpha", url: "https://a.com"),
            SearchResult(title: "Beta", url: "https://b.com"),
        ]
        let doc = Sx.renderPages(results, contents: ["<h1>A</h1>", "<h1>B</h1>"])
        #expect(doc.contains("# Alpha"))
        #expect(doc.contains("https://a.com"))
        #expect(doc.contains("<h1>A</h1>"))
        #expect(doc.contains("# Beta"))
        #expect(doc.contains("<h1>B</h1>"))
        #expect(doc.contains("---"))           // separator between the two blocks
        #expect(doc.hasSuffix("\n"))
    }

    @Test func renderPagesNotesUnreachablePage() {
        let doc = Sx.renderPages([SearchResult(title: "T", url: "https://x.com")], contents: [nil])
        #expect(doc.contains("could not fetch this page"))
    }

    @Test func renderPagesFallsBackToURLWhenTitleEmpty() {
        let doc = Sx.renderPages([SearchResult(title: "", url: "https://only-url.com")], contents: ["body"])
        #expect(doc.contains("# https://only-url.com"))
    }

    @Test func renderPagesSingleResultHasNoSeparator() {
        let doc = Sx.renderPages([SearchResult(title: "Solo", url: "https://s.com")], contents: ["x"])
        #expect(!doc.contains("\n---\n"))
    }
}
