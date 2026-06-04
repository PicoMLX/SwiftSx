import Foundation

/// Pure, stateless rendering of ``SearchResult`` arrays into the three output
/// modes of the `sx` tool.
///
/// All functions are synchronous and return `String` — no I/O, no side effects.
/// Determinism is a first-class concern: JSON output uses sorted keys and a
/// stable field order so agents can pattern-match output across runs.
public enum ResultRenderer {

    // MARK: - Private: ANSI alias

    /// Allows internal callers to write `ANSI.color(…)` — the type is the same
    /// `ResultRenderer` enum where the helper is defined as a static method.
    private typealias ANSI = ResultRenderer

    // MARK: - JSON

    /// Render results as a pretty-printed JSON envelope.
    ///
    /// The envelope shape is always `{ "query": …, "results": […] }`.  Keys are
    /// sorted, the indent is 2 spaces, and forward-slashes are not escaped.
    ///
    /// - Parameters:
    ///   - query: The search query string, echoed verbatim into the envelope.
    ///   - results: The results to serialise. May be empty.
    ///   - clean: When `true`, omit every field whose value is empty, zero,
    ///     `false`, `nil`, or an empty collection (per ``cleanDict(for:)``).
    /// - Returns: A valid JSON string, always terminated with `\n`.
    /// - Throws: `SxError(.general, …)` if `JSONSerialization` fails (should
    ///   not occur in practice given the fixed schema).
    public static func renderJSON(
        query: String,
        results: [SearchResult],
        clean: Bool
    ) throws -> String {
        let resultDicts: [Any] = results.map { result in
            clean ? cleanDict(for: result) : fullDict(for: result)
        }

        // Build the envelope as [String: Any] so JSONSerialization can sort keys.
        let envelope: [String: Any] = [
            "query": query,
            "results": resultDicts,
        ]

        let options: JSONSerialization.WritingOptions = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: envelope, options: options)
        } catch {
            throw SxError(.general, "JSON serialization failed: \(error)")
        }

        // JSONSerialization uses 2-space indent with .prettyPrinted — matches spec.
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: - Links-only

    /// Render one URL per line.
    ///
    /// - Parameter results: The results to render. Empty-URL entries are skipped.
    /// - Returns: Each non-empty URL on its own line, with a trailing newline.
    ///   Returns `""` when there are no non-empty URLs.
    public static func renderLinks(_ results: [SearchResult]) -> String {
        let urls = results.map(\.url).filter { !$0.isEmpty }
        guard !urls.isEmpty else { return "" }
        return urls.joined(separator: "\n") + "\n"
    }

    // MARK: - Plain (human-readable)

    /// Render results in a human-readable, optionally coloured format.
    ///
    /// Mirrors the presentation of the upstream Go `display.go`:
    ///
    /// 1. Query header
    /// 2. For each result: numbered entry with title, domain, optional URL,
    ///    content snippet, category-specific metadata, and engines line.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - results: The results to render.
    ///   - expand: When `true`, print the full URL beneath the header line.
    ///   - noColor: When `true`, suppress all ANSI escape codes (use in tests
    ///     and when `NO_COLOR` is set or output is not a TTY).
    /// - Returns: A formatted string ready to write to stdout.
    public static func renderPlain(
        query: String,
        results: [SearchResult],
        expand: Bool,
        noColor: Bool
    ) -> String {
        var out = ""

        // Query header
        let queryLabel = ANSI.color("Query: \(query)", .whiteBold, enabled: !noColor)
        out += "\n\(queryLabel)\n\n"

        for (index, result) in results.enumerated() {
            let number = index + 1

            // --- Title / domain header line ---
            let titleRaw = result.title.isEmpty ? "No title" : result.title
            let titleTruncated = truncateTitle(titleRaw)
            let titleColored = ANSI.color(titleTruncated, .greenBold, enabled: !noColor)

            let domain = hostComponent(of: result.url)
            let domainColored = ANSI.color(domain, .yellow, enabled: !noColor)
            let indexColored = ANSI.color(String(format: "%2d", number), .cyan, enabled: !noColor)

            out += " \(indexColored). \(titleColored) [\(domainColored)]\n"

            // --- Expanded URL ---
            if expand && !result.url.isEmpty {
                out += "     \(result.url)\n"
            }

            // --- Content snippet ---
            if !result.content.isEmpty {
                let snippet = formatSnippet(result.content)
                let wrapped = wordWrap(snippet, width: 75)
                for line in wrapped {
                    out += "     \(line)\n"
                }
            }

            // --- Category-specific metadata ---
            let categoryMeta = categoryMetadata(for: result, noColor: noColor)
            if !categoryMeta.isEmpty {
                out += "     \(categoryMeta)\n"
            }

            // --- Engines line ---
            let enginesLine = buildEnginesLine(engine: result.engine, engines: result.engines)
            let enginesColored = ANSI.color(enginesLine, .dim, enabled: !noColor)
            out += "     \(enginesColored)\n"

            // Blank line after each result
            out += "\n"
        }

        return out
    }
}

// MARK: - Private: JSON helpers

extension ResultRenderer {

    /// Build a `[String: Any]` dictionary containing every field of `result`,
    /// using the upstream JSON key names.  This produces the same shape as the
    /// `Encodable` conformance of ``SearchResult`` (same CodingKeys), but
    /// assembled manually so we can feed it to `JSONSerialization` for sorted,
    /// slash-preserving output.
    static func fullDict(for result: SearchResult) -> [String: Any] {
        var dict: [String: Any] = [
            "title":        result.title,
            "url":          result.url,
            "content":      result.content,
            "engine":       result.engine,
            "engines":      result.engines,
            "category":     result.category,
            "template":     result.template,
            "publishedDate": result.publishedDate,
            "author":       result.author,
            "source":       result.source,
            "resolution":   result.resolution,
            "img_src":      result.imgSrc,
            "longitude":    result.longitude,
            "latitude":     result.latitude,
            "journal":      result.journal,
            "publisher":    result.publisher,
            "magnetlink":   result.magnetlink,
            "seed":         result.seed,
            "leech":        result.leech,
            "filesize":     result.filesize,
            "size":         result.size,
            "metadata":     result.metadata,
        ]

        // Optional fields
        if let length = result.length {
            switch length {
            case .seconds(let v): dict["length"] = v
            case .text(let v):    dict["length"] = v
            }
        } else {
            dict["length"] = NSNull()
        }

        if let address = result.address {
            dict["address"] = address
        } else {
            dict["address"] = NSNull()
        }

        return dict
    }

    /// Build a `[String: Any]` dictionary for `result` containing **only**
    /// fields that carry a non-default value.
    ///
    /// Drop rules:
    /// - `String` → drop when `""`
    /// - `Int`    → drop when `0`
    /// - `Bool`   → drop when `false`
    /// - `nil`    → always drop
    /// - `[String]` → drop when empty
    /// - `[String: String]` → drop when empty or nil
    static func cleanDict(for result: SearchResult) -> [String: Any] {
        var dict = [String: Any]()

        func setString(_ key: String, _ value: String) {
            if !value.isEmpty { dict[key] = value }
        }
        func setInt(_ key: String, _ value: Int) {
            if value != 0 { dict[key] = value }
        }
        func setDouble(_ key: String, _ value: Double) {
            if value != 0 { dict[key] = value }
        }

        setString("title",        result.title)
        setString("url",          result.url)
        setString("content",      result.content)
        setString("engine",       result.engine)

        if !result.engines.isEmpty {
            dict["engines"] = result.engines
        }

        setString("category",     result.category)
        setString("template",     result.template)
        setString("publishedDate", result.publishedDate)
        setString("author",       result.author)

        if let length = result.length {
            switch length {
            case .seconds(let v): dict["length"] = v
            case .text(let v):    dict["length"] = v
            }
        }

        setString("source",     result.source)
        setString("resolution", result.resolution)
        setString("img_src",    result.imgSrc)

        if let address = result.address, !address.isEmpty {
            dict["address"] = address
        }

        setDouble("longitude", result.longitude)
        setDouble("latitude",  result.latitude)
        setString("journal",   result.journal)
        setString("publisher", result.publisher)
        setString("magnetlink", result.magnetlink)
        setInt("seed",  result.seed)
        setInt("leech", result.leech)
        setString("filesize",  result.filesize)
        setString("size",      result.size)
        setString("metadata",  result.metadata)

        return dict
    }
}

// MARK: - Private: Plain-text helpers

extension ResultRenderer {

    /// Truncate `title` to at most 70 characters. If truncated, replace the last
    /// three characters with `"..."`.
    static func truncateTitle(_ title: String) -> String {
        guard title.count > 70 else { return title }
        let prefix = String(title.prefix(67))
        return prefix + "..."
    }

    /// Extract the host (domain) component from a URL string.
    ///
    /// Returns `""` when `url` is empty or cannot be parsed.
    static func hostComponent(of url: String) -> String {
        guard !url.isEmpty,
              let components = URLComponents(string: url),
              let host = components.host,
              !host.isEmpty
        else { return "" }
        return host
    }

    /// Strip HTML, unescape entities, collapse whitespace, and cap at 128 words.
    ///
    /// Appends `" ..."` when the word count is exceeded.
    static func formatSnippet(_ content: String) -> String {
        // 1. Unescape basic HTML entities.
        var text = content
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")

        // 2. Strip HTML tags.
        if let regex = try? NSRegularExpression(pattern: "<[^>]*>") {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }

        // 3. Collapse whitespace (spaces, tabs, newlines → single space, trimmed).
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        // 4. Cap at 128 words.
        if words.count > 128 {
            return words.prefix(128).joined(separator: " ") + " ..."
        }
        return words.joined(separator: " ")
    }

    /// Word-wrap `text` at `width` characters, returning each line as a separate
    /// element.  Long unbreakable tokens are kept on their own line.
    static func wordWrap(_ text: String, width: Int) -> [String] {
        let words = text.components(separatedBy: " ")
        var lines = [String]()
        var current = ""

        for word in words {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    /// Build the category-specific metadata string (empty when not applicable).
    static func categoryMetadata(for result: SearchResult, noColor: Bool) -> String {
        switch result.category {
        case "news", "social media":
            let date = result.publishedDate
            guard !date.isEmpty else { return "" }
            return ANSI.color(date, .dim, enabled: !noColor)

        case "files":
            var parts = [String]()
            if !result.filesize.isEmpty { parts.append(result.filesize) }
            else if !result.size.isEmpty { parts.append(result.size) }
            if !result.magnetlink.isEmpty { parts.append(result.magnetlink) }
            guard !parts.isEmpty else { return "" }
            return ANSI.color(parts.joined(separator: "  "), .dim, enabled: !noColor)

        case "images":
            var parts = [String]()
            if !result.resolution.isEmpty { parts.append(result.resolution) }
            if !result.source.isEmpty { parts.append(result.source) }
            guard !parts.isEmpty else { return "" }
            return ANSI.color(parts.joined(separator: "  "), .dim, enabled: !noColor)

        default:
            return ""
        }
    }

    /// Build the engines bracket string, e.g. `"[brave, searxng]"`.
    ///
    /// The primary engine (`engine`) is always first; additional engines from the
    /// `engines` array that differ from `engine` are appended, comma-separated.
    static func buildEnginesLine(engine: String, engines: [String]) -> String {
        var displayed = [String]()
        if !engine.isEmpty {
            displayed.append(engine)
        }
        for e in engines where e != engine && !e.isEmpty {
            if !displayed.contains(e) {
                displayed.append(e)
            }
        }
        return "[\(displayed.joined(separator: ", "))]"
    }
}
