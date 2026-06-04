import Foundation
import Testing
@testable import SwiftSx

// MARK: - JSON rendering

@Suite struct ResultRendererJSONTests {

    // MARK: Envelope shape

    @Test func emptyResultsProducesValidEnvelope() throws {
        let json = try ResultRenderer.renderJSON(query: "hello", results: [], clean: false)
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(obj as? [String: Any])
        #expect(dict["query"] as? String == "hello")
        let results = try #require(dict["results"] as? [Any])
        #expect(results.isEmpty)
    }

    @Test func emptyResultsCleanProducesValidEnvelope() throws {
        let json = try ResultRenderer.renderJSON(query: "x", results: [], clean: true)
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(obj as? [String: Any])
        #expect(dict["query"] as? String == "x")
        let results = try #require(dict["results"] as? [Any])
        #expect(results.isEmpty)
    }

    @Test func outputTerminatesWithNewline() throws {
        let json = try ResultRenderer.renderJSON(query: "q", results: [], clean: false)
        #expect(json.hasSuffix("\n"))
    }

    @Test func keysAreSorted() throws {
        let json = try ResultRenderer.renderJSON(query: "sort-test", results: [], clean: false)
        // "query" comes before "results" alphabetically
        let queryRange = try #require(json.range(of: "\"query\""))
        let resultsRange = try #require(json.range(of: "\"results\""))
        #expect(queryRange.lowerBound < resultsRange.lowerBound)
    }

    @Test func resultKeysAreSortedAlphabetically() throws {
        let result = SearchResult(
            title: "T",
            url: "https://example.com",
            content: "C",
            engine: "brave"
        )
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)

        // In sorted order: "address", "author", "category", "content", "engine",
        // "engines", "filesize", "img_src", "journal", "latitude", "leech", "length",
        // "longitude", "magnetlink", "metadata", "publishedDate", "publisher",
        // "resolution", "seed", "size", "source", "template", "title", "url"
        // Verify at least a few stable-order pairs:
        let addressRange = try #require(json.range(of: "\"address\""))
        let contentRange = try #require(json.range(of: "\"content\""))
        let titleRange   = try #require(json.range(of: "\"title\""))
        let urlRange     = try #require(json.range(of: "\"url\""))

        #expect(addressRange.lowerBound < contentRange.lowerBound)
        #expect(contentRange.lowerBound < titleRange.lowerBound)
        #expect(titleRange.lowerBound < urlRange.lowerBound)
    }

    @Test func forwardSlashesNotEscaped() throws {
        let result = SearchResult(url: "https://example.com/path/to/page")
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        // With .withoutEscapingSlashes the slash is literal, not \/.
        #expect(json.contains("https://example.com/path/to/page"))
        #expect(!json.contains("\\/"))
    }

    @Test func queryEchoedVerbatim() throws {
        let q = "swift concurrency async/await"
        let json = try ResultRenderer.renderJSON(query: q, results: [], clean: false)
        #expect(json.contains(q))
    }

    // MARK: Non-clean (full) mode

    @Test func nonCleanIncludesEmptyStrings() throws {
        let result = SearchResult(title: "Hello", url: "https://x.com")
        // author is "" — non-clean should still include it
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        #expect(json.contains("\"author\""))
        #expect(json.contains("\"journal\""))
        #expect(json.contains("\"publisher\""))
        #expect(json.contains("\"magnetlink\""))
        #expect(json.contains("\"seed\""))
        #expect(json.contains("\"leech\""))
    }

    @Test func nonCleanIncludesNullForAbsentLength() throws {
        let result = SearchResult(title: "T")
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        // length is nil → should appear as null
        #expect(json.contains("\"length\" : null"))
    }

    @Test func nonCleanIncludesNullForAbsentAddress() throws {
        let result = SearchResult(title: "T")
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        #expect(json.contains("\"address\" : null"))
    }

    @Test func nonCleanResultRoundTripsViaDecoder() throws {
        let original = SearchResult(
            title: "Swift Concurrency",
            url: "https://swift.org/concurrency",
            content: "Structured concurrency in Swift.",
            engine: "brave",
            engines: ["brave", "searxng"],
            category: "general",
            seed: 5,
            leech: 2
        )
        let json = try ResultRenderer.renderJSON(query: "swift", results: [original], clean: false)
        let data = Data(json.utf8)
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let resultsArr = try #require(envelope?["results"] as? [[String: Any]])
        #expect(resultsArr.count == 1)
        let r = resultsArr[0]
        #expect(r["title"] as? String == "Swift Concurrency")
        #expect(r["url"] as? String == "https://swift.org/concurrency")
        #expect(r["engine"] as? String == "brave")
        #expect(r["engines"] as? [String] == ["brave", "searxng"])
        #expect(r["seed"] as? Int == 5)
        #expect(r["leech"] as? Int == 2)
    }

    // MARK: Clean mode

    @Test func cleanDropsEmptyStrings() throws {
        let result = SearchResult(title: "Only Title", url: "https://x.com", engine: "brave")
        // author, journal, publisher, magnetlink, etc. are all "" — must be absent in clean
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"author\""))
        #expect(!json.contains("\"journal\""))
        #expect(!json.contains("\"publisher\""))
        #expect(!json.contains("\"magnetlink\""))
        #expect(!json.contains("\"filesize\""))
        #expect(!json.contains("\"metadata\""))
    }

    @Test func cleanDropsZeroInts() throws {
        let result = SearchResult(title: "T", seed: 0, leech: 0)
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"seed\""))
        #expect(!json.contains("\"leech\""))
    }

    @Test func cleanKeepsNonZeroInts() throws {
        let result = SearchResult(title: "T", seed: 42, leech: 7)
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(json.contains("\"seed\""))
        #expect(json.contains("\"leech\""))
    }

    @Test func cleanDropsEmptyEnginesArray() throws {
        let result = SearchResult(title: "T", engines: [])
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"engines\""))
    }

    @Test func cleanKeepsNonEmptyEnginesArray() throws {
        let result = SearchResult(title: "T", engines: ["brave", "exa"])
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(json.contains("\"engines\""))
    }

    @Test func cleanDropsNilLength() throws {
        let result = SearchResult(title: "T")
        // length is nil — clean should NOT include "length" key
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"length\""))
    }

    @Test func cleanKeepsLengthWhenSet() throws {
        let result = SearchResult(title: "T", length: .seconds(120))
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(json.contains("\"length\""))
    }

    @Test func cleanDropsNilAddress() throws {
        let result = SearchResult(title: "T")
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"address\""))
    }

    @Test func cleanKeepsAddressWhenSet() throws {
        let result = SearchResult(title: "T", address: ["city": "Paris"])
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(json.contains("\"address\""))
        #expect(json.contains("\"city\""))
        #expect(json.contains("Paris"))
    }

    @Test func cleanDropsZeroDoubles() throws {
        let result = SearchResult(title: "T", longitude: 0, latitude: 0)
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(!json.contains("\"longitude\""))
        #expect(!json.contains("\"latitude\""))
    }

    @Test func cleanKeepsNonZeroDoubles() throws {
        let result = SearchResult(title: "T", longitude: 2.35, latitude: 48.85)
        let json = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(json.contains("\"longitude\""))
        #expect(json.contains("\"latitude\""))
    }

    @Test func cleanOnlyPopulatedFieldsForTypicalWebResult() throws {
        // A result that only has title, url, content, engine set (typical web result).
        let result = SearchResult(
            title: "Swift Docs",
            url: "https://swift.org/docs",
            content: "The official Swift documentation.",
            engine: "brave"
        )
        let json = try ResultRenderer.renderJSON(query: "swift", results: [result], clean: true)
        // Present:
        #expect(json.contains("\"title\""))
        #expect(json.contains("\"url\""))
        #expect(json.contains("\"content\""))
        #expect(json.contains("\"engine\""))
        // Absent (empty/zero defaults):
        #expect(!json.contains("\"seed\""))
        #expect(!json.contains("\"leech\""))
        #expect(!json.contains("\"longitude\""))
        #expect(!json.contains("\"latitude\""))
        #expect(!json.contains("\"length\""))
        #expect(!json.contains("\"address\""))
        #expect(!json.contains("\"engines\""))
        #expect(!json.contains("\"author\""))
        #expect(!json.contains("\"journal\""))
        #expect(!json.contains("\"publisher\""))
        #expect(!json.contains("\"magnetlink\""))
        #expect(!json.contains("\"img_src\""))
        #expect(!json.contains("\"resolution\""))
        #expect(!json.contains("\"filesize\""))
        #expect(!json.contains("\"size\""))
        #expect(!json.contains("\"metadata\""))
        #expect(!json.contains("\"publishedDate\""))
        #expect(!json.contains("\"source\""))
        #expect(!json.contains("\"category\""))
        #expect(!json.contains("\"template\""))
    }

    @Test func multipleResultsAreAllPresent() throws {
        let results = [
            SearchResult(title: "Alpha", url: "https://a.com", engine: "brave"),
            SearchResult(title: "Beta",  url: "https://b.com", engine: "exa"),
            SearchResult(title: "Gamma", url: "https://c.com", engine: "jina"),
        ]
        let json = try ResultRenderer.renderJSON(query: "multi", results: results, clean: true)
        let data = Data(json.utf8)
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = try #require(envelope?["results"] as? [[String: Any]])
        #expect(arr.count == 3)
        #expect(arr[0]["title"] as? String == "Alpha")
        #expect(arr[1]["title"] as? String == "Beta")
        #expect(arr[2]["title"] as? String == "Gamma")
    }

    @Test func outputIsDeterministicAcrossCallsNonClean() throws {
        let result = SearchResult(
            title: "Test",
            url: "https://example.com",
            content: "Snippet",
            engine: "brave",
            engines: ["brave", "exa"]
        )
        let first  = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        let second = try ResultRenderer.renderJSON(query: "q", results: [result], clean: false)
        #expect(first == second)
    }

    @Test func outputIsDeterministicAcrossCallsClean() throws {
        let result = SearchResult(
            title: "Test",
            url: "https://example.com",
            engine: "exa"
        )
        let first  = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        let second = try ResultRenderer.renderJSON(query: "q", results: [result], clean: true)
        #expect(first == second)
    }
}

// MARK: - Links-only rendering

@Suite struct ResultRendererLinksTests {

    @Test func emptyInputReturnsEmptyString() {
        let out = ResultRenderer.renderLinks([])
        #expect(out == "")
    }

    @Test func singleUrlProducesOneLineWithTrailingNewline() {
        let result = SearchResult(url: "https://example.com")
        let out = ResultRenderer.renderLinks([result])
        #expect(out == "https://example.com\n")
    }

    @Test func multipleUrlsOnePerLine() {
        let results = [
            SearchResult(url: "https://a.com"),
            SearchResult(url: "https://b.com"),
            SearchResult(url: "https://c.com"),
        ]
        let out = ResultRenderer.renderLinks(results)
        #expect(out == "https://a.com\nhttps://b.com\nhttps://c.com\n")
    }

    @Test func skipsEmptyUrls() {
        let results = [
            SearchResult(title: "No URL"),        // url == ""
            SearchResult(url: "https://x.com"),
            SearchResult(title: "Also no URL"),   // url == ""
            SearchResult(url: "https://y.com"),
        ]
        let out = ResultRenderer.renderLinks(results)
        #expect(out == "https://x.com\nhttps://y.com\n")
    }

    @Test func allEmptyUrlsReturnsEmptyString() {
        let results = [
            SearchResult(title: "A"),
            SearchResult(title: "B"),
        ]
        let out = ResultRenderer.renderLinks(results)
        #expect(out == "")
    }

    @Test func preservesUrlOrder() {
        let urls = ["https://first.com", "https://second.com", "https://third.com"]
        let results = urls.map { SearchResult(url: $0) }
        let out = ResultRenderer.renderLinks(results)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        // Last element after trailing newline will be empty — take only real lines
        let nonEmpty = lines.filter { !$0.isEmpty }
        #expect(nonEmpty.map(String.init) == urls)
    }
}

// MARK: - Plain rendering

@Suite struct ResultRendererPlainTests {

    // MARK: Query header

    @Test func headerContainsQuery() {
        let out = ResultRenderer.renderPlain(
            query: "swift concurrency",
            results: [],
            expand: false,
            noColor: true
        )
        #expect(out.contains("Query: swift concurrency"))
    }

    @Test func headerLeadingNewline() {
        let out = ResultRenderer.renderPlain(query: "q", results: [], expand: false, noColor: true)
        #expect(out.hasPrefix("\n"))
    }

    @Test func emptyResultsProducesOnlyHeader() {
        let out = ResultRenderer.renderPlain(query: "nothing", results: [], expand: false, noColor: true)
        // Should contain the header and nothing else after it
        #expect(out.contains("Query: nothing"))
        // No result numbering should appear
        #expect(!out.contains("1."))
    }

    // MARK: Result numbering and titles

    @Test func resultNumberedCorrectly() {
        let results = [
            SearchResult(title: "Alpha", url: "https://a.com", engine: "brave"),
            SearchResult(title: "Beta",  url: "https://b.com", engine: "brave"),
        ]
        let out = ResultRenderer.renderPlain(query: "q", results: results, expand: false, noColor: true)
        #expect(out.contains(" 1. Alpha"))
        #expect(out.contains(" 2. Beta"))
    }

    @Test func noTitleFallsBackToNoTitle() {
        let result = SearchResult(title: "", url: "https://x.com", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("No title"))
    }

    @Test func titleTruncatedAt70Chars() {
        // 71-char title — should be truncated to 67 + "..."
        let longTitle = String(repeating: "A", count: 71)
        let result = SearchResult(title: longTitle, url: "https://x.com", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        let expected = String(repeating: "A", count: 67) + "..."
        #expect(out.contains(expected))
    }

    @Test func titleExactly70CharsNotTruncated() {
        let title70 = String(repeating: "B", count: 70)
        let result = SearchResult(title: title70, url: "https://x.com", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // Should contain the full 70-char title, NOT truncated
        #expect(out.contains(title70))
        #expect(!out.contains(title70.prefix(67) + "..."))
    }

    @Test func titleExactly71CharsTruncated() {
        let title71 = String(repeating: "C", count: 71)
        let result = SearchResult(title: title71, url: "https://x.com", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // Must not appear verbatim (too long)
        #expect(!out.contains(title71))
        // Truncated form must appear
        #expect(out.contains(String(repeating: "C", count: 67) + "..."))
    }

    // MARK: Domain extraction

    @Test func domainExtractedFromURL() {
        let result = SearchResult(title: "T", url: "https://www.example.com/path?q=1", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("[www.example.com]"))
    }

    @Test func emptyURLProducesEmptyDomain() {
        let result = SearchResult(title: "T", url: "", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // Domain brackets should still appear but empty: "[]"
        #expect(out.contains("[]"))
    }

    // MARK: URL expansion

    @Test func expandTrueShowsURL() {
        let result = SearchResult(title: "T", url: "https://full-url.example.com/page", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: true, noColor: true)
        #expect(out.contains("     https://full-url.example.com/page"))
    }

    @Test func expandFalseHidesURL() {
        let result = SearchResult(title: "T", url: "https://full-url.example.com/page", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // URL still appears in domain [example.com] but not on its own indented line
        let lines = out.components(separatedBy: "\n")
        let expandedLine = lines.first { $0 == "     https://full-url.example.com/page" }
        #expect(expandedLine == nil)
    }

    @Test func expandSkippedWhenURLEmpty() {
        let result = SearchResult(title: "T", url: "", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: true, noColor: true)
        // With empty url, even expand: true should not emit a URL line
        let lines = out.components(separatedBy: "\n")
        let blankExpandLine = lines.first { $0 == "     " }
        #expect(blankExpandLine == nil)
    }

    // MARK: Content snippet

    @Test func contentSnippetAppearsIndented() {
        let result = SearchResult(
            title: "T",
            url: "https://x.com",
            content: "This is a short snippet.",
            engine: "brave"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("     This is a short snippet."))
    }

    @Test func htmlStrippedFromContent() {
        let result = SearchResult(
            title: "T",
            url: "https://x.com",
            content: "<b>Bold</b> and <em>italic</em> text.",
            engine: "brave"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("Bold"))
        #expect(out.contains("italic"))
        // Tags themselves should not appear
        #expect(!out.contains("<b>"))
        #expect(!out.contains("</b>"))
        #expect(!out.contains("<em>"))
    }

    @Test func htmlEntitiesUnescaped() {
        let result = SearchResult(
            title: "T",
            url: "https://x.com",
            content: "A &amp; B &lt;3 &gt;0 &quot;quoted&quot; it&#39;s",
            engine: "brave"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("A & B <3 >0 \"quoted\" it's"))
    }

    @Test func emptyContentProducesNoSnippetLines() {
        // With no content, the only indented lines should be the engines bracket.
        // We can check the output has only one "     " indented line (the engines line)
        // and that it contains "[" (the bracket).
        let result = SearchResult(title: "T", url: "https://x.com", content: "", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        let indentedLines = out.components(separatedBy: "\n").filter { $0.hasPrefix("     ") }
        // Only the engines line should be indented when there's no content
        #expect(indentedLines.count == 1)
        #expect(indentedLines[0].contains("[brave]"))
    }

    @Test func contentCappedAt128Words() {
        // Build a 130-word content string
        let words = (1...130).map { "word\($0)" }
        let content = words.joined(separator: " ")
        let result = SearchResult(title: "T", url: "https://x.com", content: content, engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // word129 and word130 must not appear; " ..." must appear
        #expect(!out.contains("word129"))
        #expect(!out.contains("word130"))
        #expect(out.contains(" ..."))
    }

    @Test func contentExactly128WordsNotTruncated() {
        let words = (1...128).map { "word\($0)" }
        let content = words.joined(separator: " ")
        let result = SearchResult(title: "T", url: "https://x.com", content: content, engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // word128 must appear and no " ..." suffix
        #expect(out.contains("word128"))
        #expect(!out.contains("word128 ..."))
    }

    // MARK: Engines line

    @Test func enginesLinePresent() {
        let result = SearchResult(title: "T", url: "https://x.com", engine: "brave")
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("[brave]"))
    }

    @Test func enginesCombinesPrimaryAndExtras() {
        let result = SearchResult(
            title: "T",
            url: "https://x.com",
            engine: "brave",
            engines: ["brave", "searxng", "exa"]
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // Primary first, then the others
        #expect(out.contains("[brave, searxng, exa]"))
    }

    @Test func enginesDeduplicatesPrimary() {
        // engine == "brave" already in engines list — should appear only once
        let result = SearchResult(
            title: "T",
            url: "https://x.com",
            engine: "brave",
            engines: ["brave", "brave"]
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // The bracket should be "[brave]" — not "[brave, brave]"
        #expect(out.contains("[brave]"))
        #expect(!out.contains("[brave, brave]"))
    }

    @Test func emptyEngineAndEmptyEnginesProducesEmptyBrackets() {
        let result = SearchResult(title: "T", url: "https://x.com", engine: "", engines: [])
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("[]"))
    }

    // MARK: Blank line between results

    @Test func blankLineAfterEachResult() {
        let results = [
            SearchResult(title: "A", url: "https://a.com", engine: "brave"),
            SearchResult(title: "B", url: "https://b.com", engine: "brave"),
        ]
        let out = ResultRenderer.renderPlain(query: "q", results: results, expand: false, noColor: true)
        // Each result block ends with a blank line (\n\n at minimum)
        #expect(out.contains("\n\n"))
    }

    // MARK: Category-specific metadata

    @Test func newsDatePrintedWhenSet() {
        let result = SearchResult(
            title: "News",
            url: "https://news.com",
            content: "",
            engine: "brave",
            category: "news",
            publishedDate: "2024-06-01"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("2024-06-01"))
    }

    @Test func newsDateNotPrintedWhenEmpty() {
        let result = SearchResult(
            title: "News",
            url: "https://news.com",
            engine: "brave",
            category: "news",
            publishedDate: ""
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // With empty publishedDate and no content, only the engines line should be indented.
        let indentedLines = out.components(separatedBy: "\n").filter { $0.hasPrefix("     ") }
        #expect(indentedLines.count == 1)
        // That single indented line must be the engines bracket, not a date.
        #expect(indentedLines[0].contains("[brave]"))
    }

    @Test func socialMediaDatePrinted() {
        let result = SearchResult(
            title: "Post",
            url: "https://social.example.com",
            engine: "brave",
            category: "social media",
            publishedDate: "2024-05-15"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("2024-05-15"))
    }

    @Test func filesFilesizePrinted() {
        let result = SearchResult(
            title: "Archive",
            url: "https://files.example.com/a.zip",
            engine: "brave",
            category: "files",
            filesize: "12 MB"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("12 MB"))
    }

    @Test func filesFallsBackToSizeWhenFilesizeEmpty() {
        let result = SearchResult(
            title: "Archive",
            url: "https://files.example.com/a.zip",
            engine: "brave",
            category: "files",
            filesize: "",
            size: "9999 bytes"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("9999 bytes"))
    }

    @Test func filesMagnetlinkPrinted() {
        let result = SearchResult(
            title: "Torrent",
            url: "https://tracker.example.com",
            engine: "brave",
            category: "files",
            filesize: "700 MB",
            magnetlink: "magnet:?xt=urn:btih:abc"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("700 MB"))
        #expect(out.contains("magnet:?xt=urn:btih:abc"))
    }

    @Test func imagesResolutionAndSourcePrinted() {
        let result = SearchResult(
            title: "Photo",
            url: "https://img.example.com/photo.jpg",
            engine: "brave",
            category: "images",
            resolution: "1920x1080",
            source: "Flickr"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(out.contains("1920x1080"))
        #expect(out.contains("Flickr"))
    }

    @Test func generalCategoryNoExtraMetadata() {
        // For a "general" category result, no special category line should appear
        // beyond what normal rendering does (engines, content).
        let result = SearchResult(
            title: "General",
            url: "https://example.com",
            content: "Some content.",
            engine: "brave",
            category: "general",
            publishedDate: "2024-01-01" // should NOT show for "general"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        // publishedDate should not appear as a dedicated line for "general"
        #expect(!out.contains("2024-01-01"))
    }

    // MARK: noColor mode

    @Test func noColorProducesNoEscapeCodes() {
        let result = SearchResult(
            title: "Colorless",
            url: "https://x.com",
            content: "Content here.",
            engine: "brave"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: true)
        #expect(!out.contains("\u{001B}"))
    }

    @Test func colorModeProducesEscapeCodes() {
        let result = SearchResult(
            title: "Colorful",
            url: "https://x.com",
            content: "Content.",
            engine: "brave"
        )
        let out = ResultRenderer.renderPlain(query: "q", results: [result], expand: false, noColor: false)
        #expect(out.contains("\u{001B}"))
    }

    // MARK: ANSI helper directly

    @Test func ansiColorEnabledWrapsText() {
        let result = ResultRenderer.color("hello", .cyan, enabled: true)
        #expect(result.hasPrefix("\u{001B}["))
        #expect(result.contains("hello"))
        #expect(result.hasSuffix("\u{001B}[0m"))
    }

    @Test func ansiColorDisabledReturnsPlain() {
        let result = ResultRenderer.color("hello", .cyan, enabled: false)
        #expect(result == "hello")
    }

    // MARK: Word wrap

    @Test func wordWrapBreaksAtWidth() {
        // A string whose words exceed 75 chars should be broken across lines
        let text = Array(repeating: "word", count: 30).joined(separator: " ")
        // 30 * 4 + 29 = 149 chars total — must produce multiple wrapped lines
        let lines = ResultRenderer.wordWrap(text, width: 75)
        #expect(lines.count > 1)
        for line in lines {
            #expect(line.count <= 75)
        }
    }

    @Test func wordWrapShortTextSingleLine() {
        let text = "A short line."
        let lines = ResultRenderer.wordWrap(text, width: 75)
        #expect(lines == ["A short line."])
    }

    @Test func wordWrapEmptyTextReturnsEmpty() {
        let lines = ResultRenderer.wordWrap("", width: 75)
        #expect(lines.isEmpty)
    }

    // MARK: truncateTitle helper

    @Test func truncateTitleExact70NotTruncated() {
        let t = String(repeating: "x", count: 70)
        #expect(ResultRenderer.truncateTitle(t) == t)
    }

    @Test func truncateTitleOver70Truncated() {
        let t = String(repeating: "x", count: 80)
        let result = ResultRenderer.truncateTitle(t)
        #expect(result.count == 70)
        #expect(result.hasSuffix("..."))
    }

    // MARK: hostComponent helper

    @Test func hostComponentExtractsHost() {
        #expect(ResultRenderer.hostComponent(of: "https://www.swift.org/docs") == "www.swift.org")
    }

    @Test func hostComponentEmptyOnBadURL() {
        #expect(ResultRenderer.hostComponent(of: "not a url") == "")
    }

    @Test func hostComponentEmptyOnEmptyString() {
        #expect(ResultRenderer.hostComponent(of: "") == "")
    }
}
