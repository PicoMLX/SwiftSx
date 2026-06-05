import Foundation

/// Extracts the main readable content from an HTML document and converts it to Markdown-ish text.
///
/// This is a lightweight "readability"-style extractor used by SwiftSx's `--text` mode to turn
/// a fetched web page into clean, LLM-friendly Markdown without any external dependencies.
/// All processing is pure and deterministic — no I/O, no shared mutable state.
public enum HTMLExtractor {

    // MARK: - Public

    /// Extracts the main readable content of an HTML document as Markdown-ish text.
    ///
    /// Processing pipeline:
    /// 1. Strip non-content regions (`<script>`, `<style>`, `<head>`, etc.).
    /// 2. Pick the main content region (`<article>` > `<main>` > `<body>` > whole string).
    /// 3. Convert block and inline tags to Markdown equivalents.
    /// 4. Strip all remaining HTML tags.
    /// 5. Decode HTML entities.
    /// 6. Normalise whitespace.
    ///
    /// - Parameter html: The raw HTML string to process.
    /// - Returns: Clean Markdown-ish text, or an empty string for empty input.
    public static func extract(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var result = html
        result = stripRegions(result)
        result = pickMainRegion(result)
        result = convertBlockTags(result)
        result = convertInlineTags(result)
        result = stripRemainingTags(result)
        result = decodeEntities(result)
        result = normaliseWhitespace(result)
        return result
    }

    // MARK: - Private helpers

    /// Strips non-content regions entirely (tag + inner content).
    ///
    /// Removes: `<script>`, `<style>`, `<head>`, `<noscript>`, `<svg>`, and HTML comments.
    private static func stripRegions(_ s: String) -> String {
        let tags = ["script", "style", "head", "noscript", "svg"]
        var result = s

        for tag in tags {
            // Match opening tag (with optional attributes) through closing tag, across newlines.
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }

        // Strip HTML comments: <!-- ... -->
        if let re = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result
    }

    /// Picks the main content region from the stripped HTML.
    ///
    /// Preference order: `<article>` > `<main>` > `<body>` > whole string.
    private static func pickMainRegion(_ s: String) -> String {
        for tag in ["article", "main", "body"] {
            if let inner = extractInner(tag: tag, from: s) {
                return inner
            }
        }
        return s
    }

    /// Extracts the inner HTML of the first occurrence of a given tag (case-insensitive).
    ///
    /// - Parameters:
    ///   - tag: The tag name (e.g. `"article"`).
    ///   - s: The HTML string to search.
    /// - Returns: The inner HTML string, or `nil` if the tag is not found.
    private static func extractInner(tag: String, from s: String) -> String? {
        // Matches the opening tag (with optional attributes) and captures the inner content.
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = re.firstMatch(in: s, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: s) else {
            return nil
        }
        return String(s[captureRange])
    }

    /// Converts block-level HTML tags to their Markdown equivalents.
    ///
    /// Handles headings, paragraphs, divs, sections, list items, blockquotes, and preformatted blocks.
    private static func convertBlockTags(_ s: String) -> String {
        var result = s

        // <pre>…</pre> → fenced code block (process before <code> to avoid double-wrapping)
        if let re = try? NSRegularExpression(pattern: "<pre[^>]*>([\\s\\S]*?)</pre>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n```\n$1\n```\n")
        }

        // <blockquote>…</blockquote> — prefix each line with "> "
        result = convertBlockquotes(result)

        // <li>…</li> → "- …" (before stripping closing tags)
        if let re = try? NSRegularExpression(pattern: "<li[^>]*>([\\s\\S]*?)</li>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n- $1")
        }

        // Headings h1–h6: opening tag → Markdown prefix.
        // Use (?=[ \t>]) after the tag name so <h1> matches but <h10> does not.
        let headings = [("h1", "#"), ("h2", "##"), ("h3", "###"), ("h4", "####"), ("h5", "#####"), ("h6", "######")]
        for (tag, marker) in headings {
            if let re = try? NSRegularExpression(pattern: "<\(tag)(?=[ \\t>])[^>]*>", options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n\(marker) ")
            }
            if let re = try? NSRegularExpression(pattern: "</\(tag)>", options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
            }
        }

        // <br> / <br/> / <br /> → newline
        if let re = try? NSRegularExpression(pattern: "<br\\s*/?>", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n")
        }

        // Closing block tags that represent paragraph boundaries → blank line
        let blockClosers = ["p", "div", "section", "article", "main", "header", "footer", "nav", "ul", "ol"]
        for tag in blockClosers {
            if let re = try? NSRegularExpression(pattern: "</\(tag)>", options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
            }
        }

        return result
    }

    /// Converts `<blockquote>…</blockquote>` blocks so each inner line is prefixed with `> `.
    ///
    /// Handles nested blockquotes implicitly through repeated application.
    private static func convertBlockquotes(_ s: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: "<blockquote[^>]*>([\\s\\S]*?)</blockquote>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return s }

        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = re.matches(in: s, range: fullRange)

        guard !matches.isEmpty else { return s }

        var result = ""
        var lastEnd = s.startIndex

        for match in matches {
            // Text before this match
            if let matchStart = Range(match.range, in: s)?.lowerBound {
                result += s[lastEnd..<matchStart]
            }

            if match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: s) {
                let inner = String(s[captureRange])
                // Prefix each non-empty line with "> "
                let prefixed = inner
                    .components(separatedBy: "\n")
                    .map { line in line.isEmpty ? ">" : "> \(line)" }
                    .joined(separator: "\n")
                result += "\n\(prefixed)\n"
            }

            if let matchEnd = Range(match.range, in: s)?.upperBound {
                lastEnd = matchEnd
            }
        }

        result += s[lastEnd...]
        return result
    }

    /// Converts inline HTML tags to their Markdown equivalents.
    ///
    /// Handles links, bold, italic, and inline code.
    private static func convertInlineTags(_ s: String) -> String {
        var result = s

        // <a href="URL">TEXT</a> → [TEXT](URL)
        // Also handles single-quoted href and href with no quotes (unlikely but handled gracefully).
        result = convertLinks(result)

        // <strong>…</strong> and <b>…</b> → **…**
        // Use (?=[ \t>]) to avoid matching tags like <button> when scanning for <b>.
        for tag in ["strong", "b"] {
            if let re = try? NSRegularExpression(pattern: "<\(tag)(?=[ \\t>])[^>]*>([\\s\\S]*?)</\(tag)>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "**$1**")
            }
        }

        // <em>…</em> and <i>…</i> → *…*
        // Use (?=[ \t>]) to avoid matching tags like <input> when scanning for <i>.
        for tag in ["em", "i"] {
            if let re = try? NSRegularExpression(pattern: "<\(tag)(?=[ \\t>])[^>]*>([\\s\\S]*?)</\(tag)>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "*$1*")
            }
        }

        // <code>…</code> → `…` (inline; <pre><code> is already handled as fenced block)
        if let re = try? NSRegularExpression(pattern: "<code[^>]*>([\\s\\S]*?)</code>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "`$1`")
        }

        return result
    }

    /// Converts `<a href="…">TEXT</a>` to `[TEXT](URL)` Markdown link syntax.
    ///
    /// Falls back to plain TEXT when no `href` attribute is present.
    private static func convertLinks(_ s: String) -> String {
        // Match <a ...href="URL"...>TEXT</a> with double-quoted href
        guard let reWithHref = try? NSRegularExpression(
            pattern: "<a[^>]+href=[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return s }

        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = reWithHref.matches(in: s, range: fullRange)

        var result = ""
        var lastEnd = s.startIndex

        for match in matches {
            if let matchRange = Range(match.range, in: s) {
                result += s[lastEnd..<matchRange.lowerBound]

                let url: String
                if match.numberOfRanges > 1, let urlRange = Range(match.range(at: 1), in: s) {
                    url = String(s[urlRange])
                } else {
                    url = ""
                }

                let text: String
                if match.numberOfRanges > 2, let textRange = Range(match.range(at: 2), in: s) {
                    text = String(s[textRange])
                } else {
                    text = ""
                }

                if url.isEmpty {
                    result += text
                } else {
                    result += "[\(text)](\(url))"
                }

                lastEnd = matchRange.upperBound
            }
        }

        result += s[lastEnd...]

        // Remaining <a> tags without href → strip tags, keep inner text
        if let reNoHref = try? NSRegularExpression(
            pattern: "<a[^>]*>([\\s\\S]*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = reNoHref.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }

        return result
    }

    /// Strips all remaining HTML tags from the string.
    private static func stripRemainingTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    /// Decodes common HTML entities to their Unicode equivalents.
    ///
    /// Named entities decoded: `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&apos;`, `&nbsp;`.
    /// Numeric entities decoded: `&#NN;` (decimal) and `&#xHH;` (hexadecimal).
    /// `&amp;` is decoded last to prevent double-unescaping.
    private static func decodeEntities(_ s: String) -> String {
        var result = s

        // Named entities (decode &amp; last)
        let namedEntities: [(String, String)] = [
            ("&lt;",   "<"),
            ("&gt;",   ">"),
            ("&quot;", "\""),
            ("&#39;",  "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // Decimal numeric entities: &#NN;
        if let re = try? NSRegularExpression(pattern: "&#([0-9]{1,6});", options: []) {
            result = replaceNumericEntities(result, regex: re, radix: 10)
        }

        // Hexadecimal numeric entities: &#xHH; or &#XHH;
        if let re = try? NSRegularExpression(pattern: "&#[xX]([0-9a-fA-F]{1,6});", options: []) {
            result = replaceNumericEntities(result, regex: re, radix: 16)
        }

        // &amp; decoded last
        result = result.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)

        return result
    }

    /// Replaces numeric HTML entities matched by `regex` using the given `radix`.
    ///
    /// - Parameters:
    ///   - s: The input string containing encoded entities.
    ///   - regex: A compiled `NSRegularExpression` whose capture group 1 holds the code-point digits.
    ///   - radix: 10 for decimal entities, 16 for hexadecimal.
    /// - Returns: The string with matched entities replaced by their Unicode scalar values.
    private static func replaceNumericEntities(_ s: String, regex: NSRegularExpression, radix: Int) -> String {
        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: s, range: fullRange)

        guard !matches.isEmpty else { return s }

        var result = ""
        var lastEnd = s.startIndex

        for match in matches {
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: s),
                  let matchRange = Range(match.range, in: s) else {
                continue
            }

            result += s[lastEnd..<matchRange.lowerBound]

            let digits = String(s[captureRange])
            if let codePoint = UInt32(digits, radix: radix),
               let scalar = Unicode.Scalar(codePoint) {
                result += String(scalar)
            } else {
                // Keep the original entity unchanged if decoding fails.
                result += String(s[matchRange])
            }

            lastEnd = matchRange.upperBound
        }

        result += s[lastEnd...]
        return result
    }

    /// Normalises whitespace in the extracted Markdown text.
    ///
    /// - Collapses runs of spaces and tabs on the same line to a single space.
    /// - Trims trailing spaces from each line.
    /// - Collapses three or more consecutive blank lines to exactly two newlines (one blank line).
    /// - Trims leading and trailing whitespace from the final result.
    private static func normaliseWhitespace(_ s: String) -> String {
        var result = s

        // Collapse runs of horizontal whitespace (spaces/tabs) to a single space.
        if let re = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }

        // Trim trailing spaces on each line.
        if let re = try? NSRegularExpression(pattern: " +$", options: [.anchorsMatchLines]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Collapse 3+ consecutive newlines to exactly 2.
        if let re = try? NSRegularExpression(pattern: "\\n{3,}", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
