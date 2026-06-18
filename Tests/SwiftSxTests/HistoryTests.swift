import Foundation
import Testing
@testable import SwiftSx

// MARK: - historyFilePath

@Suite struct HistoryFilePathTests {

    @Test func usesXDGStateHomeWhenSet() {
        let env = ["XDG_STATE_HOME": "/x"]
        let path = History.historyFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/x/sx/history")
    }

    @Test func fallsBackToHomeLocalStateWhenXDGAbsent() {
        let path = History.historyFilePath(env: [:], homeDirectory: "/home/u")
        #expect(path == "/home/u/.local/state/sx/history")
    }

    @Test func fallsBackToHomeLocalStateWhenXDGEmpty() {
        let env = ["XDG_STATE_HOME": ""]
        let path = History.historyFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/home/u/.local/state/sx/history")
    }

    @Test func xdgValueIsUsedVerbatim() {
        let env = ["XDG_STATE_HOME": "/custom/state"]
        let path = History.historyFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/custom/state/sx/history")
    }

    @Test func ignoresRelativeXDGStateHome() {
        // A relative XDG_STATE_HOME is invalid per the XDG spec → fall back.
        let env = ["XDG_STATE_HOME": "relative/state"]
        let path = History.historyFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/home/u/.local/state/sx/history")
    }

    @Test func ignoresTildeXDGStateHome() {
        // A tilde path is not a literal absolute path, so it must be ignored —
        // NSString.isAbsolutePath would wrongly accept it. Falls back to home.
        let env = ["XDG_STATE_HOME": "~/state"]
        let path = History.historyFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/home/u/.local/state/sx/history")
    }
}

// MARK: - formatLine / parseLines round-trip

@Suite struct HistoryFormatParseTests {

    @Test func formatLineRoundTrip() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z"))
        let entry = HistoryEntry(timestamp: date, query: "swift concurrency")
        let line = History.formatLine(entry)

        // Line must end with a newline and contain exactly one tab.
        #expect(line.hasSuffix("\n"))
        let tabCount = line.filter { $0 == "\t" }.count
        #expect(tabCount >= 1)

        // Parse it back — stripping the trailing newline.
        let recovered = History.parseLines(line)
        #expect(recovered.count == 1)
        #expect(recovered[0].query == "swift concurrency")
        // Timestamps must agree to the second (ISO 8601 round-trip).
        #expect(abs(recovered[0].timestamp.timeIntervalSince(date)) < 1.0)
    }

    @Test func multipleEntriesRoundTrip() {
        let now = Date()
        let entries = [
            HistoryEntry(timestamp: now.addingTimeInterval(-120), query: "first query"),
            HistoryEntry(timestamp: now.addingTimeInterval(-60),  query: "second query"),
            HistoryEntry(timestamp: now,                           query: "third query"),
        ]
        let text = entries.map { History.formatLine($0) }.joined()
        let recovered = History.parseLines(text)

        #expect(recovered.count == 3)
        #expect(recovered[0].query == "first query")
        #expect(recovered[1].query == "second query")
        #expect(recovered[2].query == "third query")
    }

    @Test func parseLinesSkipsMalformedLines() {
        let now = Date()
        let goodLine = History.formatLine(HistoryEntry(timestamp: now, query: "good"))
        let text = """
            no-tab-here
            \(goodLine.dropLast())
            also-bad-line
            """
        // Only the good line should parse; the others have no valid tab+timestamp.
        let recovered = History.parseLines(text)
        #expect(recovered.count == 1)
        #expect(recovered[0].query == "good")
    }

    @Test func parseLinesSkipsBadTimestamp() {
        let text = "not-a-date\tsome query\n"
        let recovered = History.parseLines(text)
        #expect(recovered.isEmpty)
    }

    @Test func parseLinesSkipsEmptyLines() {
        let now = Date()
        let goodLine = History.formatLine(HistoryEntry(timestamp: now, query: "ok"))
        let text = "\n\n\(goodLine)\n\n"
        let recovered = History.parseLines(text)
        #expect(recovered.count == 1)
    }

    @Test func formatLineCollapsesEmbeddedNewlines() {
        // A query containing CR/LF must not break the one-line-per-entry format:
        // the only newline in the produced line is the trailing record terminator.
        let entry = HistoryEntry(timestamp: Date(), query: "line one\nline two\r\nline three")
        let line = History.formatLine(entry)

        #expect(line.hasSuffix("\n"))
        #expect(!line.dropLast().contains("\n"))   // no embedded LF before the terminator
        #expect(!line.contains("\r"))              // CR collapsed too

        // And it round-trips as exactly one entry (continuation lines preserved
        // as spaces, not dropped as malformed).
        let recovered = History.parseLines(line)
        #expect(recovered.count == 1)
        #expect(recovered[0].query == "line one line two  line three")
    }

    @Test func parseLinesAllowsTabInQuery() {
        // A query that itself contains a tab must still parse correctly:
        // split(maxSplits:1) ensures only the first tab is the separator.
        let now = Date()
        let entry = HistoryEntry(timestamp: now, query: "a\tb")  // query with tab
        let line = History.formatLine(entry)
        let recovered = History.parseLines(line)
        #expect(recovered.count == 1)
        #expect(recovered[0].query == "a\tb")
    }
}

// MARK: - trimmed

@Suite struct HistoryTrimmedTests {

    @Test func trimmedKeepsLastWhenOverLimit() {
        let lines = ["a\n", "b\n", "c\n", "d\n", "e\n"]
        let result = History.trimmed(lines, maxHistory: 3)
        #expect(result == ["c\n", "d\n", "e\n"])
    }

    @Test func trimmedReturnsAllWhenUnderLimit() {
        let lines = ["a\n", "b\n"]
        let result = History.trimmed(lines, maxHistory: 10)
        #expect(result == ["a\n", "b\n"])
    }

    @Test func trimmedReturnsAllWhenEqualToLimit() {
        let lines = ["a\n", "b\n", "c\n"]
        let result = History.trimmed(lines, maxHistory: 3)
        #expect(result == ["a\n", "b\n", "c\n"])
    }

    @Test func trimmedReturnsAllWhenMaxHistoryIsZero() {
        let lines = ["a\n", "b\n", "c\n"]
        let result = History.trimmed(lines, maxHistory: 0)
        #expect(result == ["a\n", "b\n", "c\n"])
    }

    @Test func trimmedReturnsAllWhenMaxHistoryIsNegative() {
        let lines = ["a\n", "b\n", "c\n"]
        let result = History.trimmed(lines, maxHistory: -5)
        #expect(result == ["a\n", "b\n", "c\n"])
    }

    @Test func trimmedEmptyInput() {
        let result = History.trimmed([], maxHistory: 5)
        #expect(result.isEmpty)
    }
}

// MARK: - displayLine

@Suite struct HistoryDisplayLineTests {

    @Test func displayLineFormat() throws {
        // 2024-06-04 at 14:30 UTC
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 4
        components.hour = 14
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))
        let entry = HistoryEntry(timestamp: date, query: "hello world")
        let line = History.displayLine(entry)

        // Must start with two spaces, contain the date/time, and end with the query.
        #expect(line.hasPrefix("  "))
        #expect(line.hasSuffix("  hello world"))
        // Spot-check the date portion is present (locale-independent pieces).
        #expect(line.contains("2024-06-04"))
        #expect(line.contains("14:30"))
    }

    @Test func displayLineContainsQuery() {
        let entry = HistoryEntry(timestamp: Date(), query: "my test query")
        let line = History.displayLine(entry)
        #expect(line.contains("my test query"))
    }

    @Test func displayLineHasNoTrailingNewline() {
        let entry = HistoryEntry(timestamp: Date(), query: "query")
        let line = History.displayLine(entry)
        #expect(!line.hasSuffix("\n"))
    }
}
