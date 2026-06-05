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
    /// 1. Protect `<pre>` blocks with placeholder tokens.
    /// 2. Strip non-content regions (`<script>`, `<style>`, `<head>`, etc.).
    /// 3. Pick the main content region (`<article>` > `<main>` > `<body>` > whole string).
    /// 4. Convert `<br>` and `<p>` block tags to newlines (needed before blockquote handling).
    /// 5. Convert blockquote blocks, prefixing each inner line with `> `.
    /// 6. Convert remaining block and inline tags to Markdown equivalents.
    /// 7. Strip all remaining HTML tags.
    /// 8. Decode HTML entities.
    /// 9. Normalise whitespace.
    /// 10. Restore `<pre>` placeholders as fenced code blocks.
    ///
    /// - Parameter html: The raw HTML string to process.
    /// - Returns: Clean Markdown-ish text, or an empty string for empty input.
    public static func extract(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var result = html

        // Step 1: Protect <pre> blocks before any transformation.
        var preBlocks: [String] = []
        result = protectPreBlocks(result, captured: &preBlocks)

        // Step 2: Strip non-content regions.
        result = stripRegions(result)

        // Step 3: Pick the main content region.
        result = pickMainRegion(result)

        // Step 4: Convert <br> and paragraph/block tags to newlines first
        //         so that blockquote inner text is already line-broken.
        result = convertBrAndParagraphTags(result)

        // Step 5: Convert blockquotes (after inner <p>/<br> have become newlines).
        result = convertBlockquotes(result)

        // Step 6: Convert remaining block and inline tags.
        result = convertBlockTags(result)
        result = convertInlineTags(result)

        // Step 7: Strip remaining HTML tags.
        result = stripRemainingTags(result)

        // Step 8: Decode HTML entities.
        result = decodeEntities(result)

        // Step 9: Normalise whitespace.
        result = normaliseWhitespace(result)

        // Step 10: Restore <pre> blocks as fenced code blocks.
        result = restorePreBlocks(result, captured: preBlocks)

        return result
    }

    // MARK: - Precompiled regular expressions
    //
    // NSRegularExpression is documented as immutable and thread-safe for matching.
    // `nonisolated(unsafe)` satisfies Swift 6 strict-concurrency without wrapping the
    // instances in a lock — they are never mutated after initialisation.

    private static func makeRE(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        // Force-try is intentional: a bad literal pattern is a programmer error caught at startup.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func makeREDotAll(_ pattern: String) -> NSRegularExpression {
        makeRE(pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    // Pre-block protection
    // `(?=[\s>/])` accepts space, tab, newline, CR — any HTML whitespace before an attribute.
    nonisolated(unsafe) private static let rePreBlock: NSRegularExpression =
        makeREDotAll("<pre(?=[\\s>/])[^>]*>([\\s\\S]*?)</pre>")

    // Strip regions
    nonisolated(unsafe) private static let reRegionScript: NSRegularExpression =
        makeREDotAll("<script(?=[\\s>/])[^>]*>[\\s\\S]*?</script>")
    nonisolated(unsafe) private static let reRegionStyle: NSRegularExpression =
        makeREDotAll("<style(?=[\\s>/])[^>]*>[\\s\\S]*?</style>")
    nonisolated(unsafe) private static let reRegionHead: NSRegularExpression =
        makeREDotAll("<head(?=[\\s>/])[^>]*>[\\s\\S]*?</head>")
    nonisolated(unsafe) private static let reRegionNoscript: NSRegularExpression =
        makeREDotAll("<noscript(?=[\\s>/])[^>]*>[\\s\\S]*?</noscript>")
    nonisolated(unsafe) private static let reRegionSvg: NSRegularExpression =
        makeREDotAll("<svg(?=[\\s>/])[^>]*>[\\s\\S]*?</svg>")
    nonisolated(unsafe) private static let reHtmlComment: NSRegularExpression =
        makeREDotAll("<!--[\\s\\S]*?-->")

    // Main-region extraction
    // `(?=[\s>/])` handles attributes that wrap across lines, e.g. `<article\n  class="post">`.
    nonisolated(unsafe) private static let reInnerArticle: NSRegularExpression =
        makeREDotAll("<article(?=[\\s>/])[^>]*>([\\s\\S]*?)</article>")
    nonisolated(unsafe) private static let reInnerMain: NSRegularExpression =
        makeREDotAll("<main(?=[\\s>/])[^>]*>([\\s\\S]*?)</main>")
    nonisolated(unsafe) private static let reInnerBody: NSRegularExpression =
        makeREDotAll("<body(?=[\\s>/])[^>]*>([\\s\\S]*?)</body>")

    // <br> → newline
    nonisolated(unsafe) private static let reBr: NSRegularExpression =
        makeRE("<br\\s*/?>")

    // Opening block tags → blank line separator (single combined pass).
    // `(?=[\s>/])` keeps the tag-boundary guard so e.g. `<paragraph>` is not matched.
    // `<li>` is intentionally excluded because `reLi` handles the full `<li>…</li>` block.
    nonisolated(unsafe) private static let reBlockOpeners: NSRegularExpression =
        makeRE("<(p|div|section|article|main|header|footer|nav|ul|ol)(?=[\\s>/])[^>]*>")

    // Closing block tags → blank line (combined single pass)
    nonisolated(unsafe) private static let reBlockClosers: NSRegularExpression =
        makeRE("</(p|div|section|article|main|header|footer|nav|ul|ol)>")

    // Blockquote
    nonisolated(unsafe) private static let reBlockquote: NSRegularExpression =
        makeREDotAll("<blockquote(?=[\\s>/])[^>]*>([\\s\\S]*?)</blockquote>")

    // List items
    nonisolated(unsafe) private static let reLi: NSRegularExpression =
        makeREDotAll("<li(?=[\\s>/])[^>]*>([\\s\\S]*?)</li>")

    // Headings: (regex, marker) pairs — built once.
    // `(?=[\s>])` handles newlines in attributes while still rejecting e.g. `<h10>`
    // (the digit `0` is not in `[\s>]`).
    nonisolated(unsafe) private static let headingPatterns: [(open: NSRegularExpression, close: NSRegularExpression, marker: String)] = {
        let defs: [(String, String)] = [
            ("h1", "#"), ("h2", "##"), ("h3", "###"),
            ("h4", "####"), ("h5", "#####"), ("h6", "######"),
        ]
        return defs.map { tag, marker in
            let open  = makeRE("<\(tag)(?=[\\s>])[^>]*>")
            let close = makeRE("</\(tag)>")
            return (open, close, marker)
        }
    }()

    // Inline bold / italic / code / links
    // `(?=[\s>])` covers multi-line opening tags.
    nonisolated(unsafe) private static let reBold: [(NSRegularExpression)] = {
        ["strong", "b"].map { tag in
            makeREDotAll("<\(tag)(?=[\\s>])[^>]*>([\\s\\S]*?)</\(tag)>")
        }
    }()

    nonisolated(unsafe) private static let reItalic: [(NSRegularExpression)] = {
        ["em", "i"].map { tag in
            makeREDotAll("<\(tag)(?=[\\s>])[^>]*>([\\s\\S]*?)</\(tag)>")
        }
    }()

    nonisolated(unsafe) private static let reInlineCode: NSRegularExpression =
        makeREDotAll("<code(?=[\\s>/])[^>]*>([\\s\\S]*?)</code>")

    // Link with href — supports:
    //   href="url"     (double-quoted)  → capture group 1
    //   href='url'     (single-quoted)  → capture group 2
    //   href=url       (unquoted)       → capture group 3
    //   href = "url"   (spaces around =) — handled by \s* between href, = and value
    // Link text is capture group 4.
    // `(?=[\s>])` on the opening <a …> tag boundary.
    nonisolated(unsafe) private static let reLinkWithHref: NSRegularExpression =
        makeREDotAll("<a(?=[\\s>])[^>]+href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))[^>]*>([\\s\\S]*?)</a>")

    nonisolated(unsafe) private static let reLinkNoHref: NSRegularExpression =
        makeREDotAll("<a(?=[\\s>])[^>]*>([\\s\\S]*?)</a>")

    // Strip remaining tags
    nonisolated(unsafe) private static let reAnyTag: NSRegularExpression =
        makeRE("<[^>]+>", options: [])

    // Whitespace normalisation
    nonisolated(unsafe) private static let reHorizontalWS: NSRegularExpression =
        makeRE("[ \\t]+", options: [])
    nonisolated(unsafe) private static let reTrailingSpaceOnLine: NSRegularExpression =
        makeRE(" +$", options: [.anchorsMatchLines])
    nonisolated(unsafe) private static let reMultiNewline: NSRegularExpression =
        makeRE("\\n{3,}", options: [])

    // Inner-code tags inside <pre> content
    nonisolated(unsafe) private static let reInnerCodeTag: NSRegularExpression =
        makeRE("</?code[^>]*>")

    // Decimal and hex numeric entities
    nonisolated(unsafe) private static let reDecimalEntity: NSRegularExpression =
        makeRE("&#([0-9]{1,6});", options: [])
    nonisolated(unsafe) private static let reHexEntity: NSRegularExpression =
        makeRE("&#[xX]([0-9a-fA-F]{1,6});", options: [])

    // MARK: - Private helpers

    // MARK: Pre-block protection

    /// Replaces every `<pre>…</pre>` block with a private-use-area placeholder token so that
    /// subsequent passes (entity decoding, whitespace collapsing, inline-code conversion)
    /// cannot corrupt the block's content.
    ///
    /// - Parameters:
    ///   - s: The HTML string.
    ///   - captured: Out-parameter that receives the raw inner HTML of each captured block,
    ///     in order of appearance.
    /// - Returns: The HTML string with `<pre>` blocks replaced by placeholder tokens.
    private static func protectPreBlocks(_ s: String, captured: inout [String]) -> String {
        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = rePreBlock.matches(in: s, range: fullRange)

        guard !matches.isEmpty else { return s }

        var result = ""
        var lastEnd = s.startIndex

        for (i, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: s) else { continue }

            result += s[lastEnd..<matchRange.lowerBound]

            // Capture the inner HTML (group 1).
            let inner: String
            if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: s) {
                inner = String(s[captureRange])
            } else {
                inner = ""
            }
            captured.append(inner)

            // Emit a placeholder that contains no spaces, tags, entities, or newlines.
            result += "\u{E000}SXPRE\(i)\u{E000}"
            lastEnd = matchRange.upperBound
        }

        result += s[lastEnd...]
        return result
    }

    /// Restores placeholder tokens inserted by `protectPreBlocks(_:captured:)` as fenced
    /// code blocks.  The inner content has its `<code>` wrapper stripped, then all remaining
    /// HTML tags (e.g. syntax-highlight `<span>` markup) stripped, and finally HTML entities
    /// decoded — so escaped code literals (`&lt;`, `&amp;`) decode correctly. Whitespace is
    /// preserved verbatim (the whitespace-collapse pass never sees this content).
    ///
    /// - Parameters:
    ///   - s: The processed string still containing placeholder tokens.
    ///   - captured: The raw inner HTML captured during protection, in the same order.
    /// - Returns: The string with each placeholder replaced by a fenced code block.
    private static func restorePreBlocks(_ s: String, captured: [String]) -> String {
        var result = s
        for (i, rawInner) in captured.enumerated() {
            let placeholder = "\u{E000}SXPRE\(i)\u{E000}"

            // Step A: Strip any <code>…</code> wrapper tags (but keep their text content).
            var inner = reInnerCodeTag.stringByReplacingMatches(
                in: rawInner,
                range: NSRange(rawInner.startIndex..., in: rawInner),
                withTemplate: ""
            )

            // Step B: Strip all remaining HTML tags (e.g. syntax-highlight <span> markup).
            // This removes <span class="k"> etc. while leaving the text content intact.
            inner = reAnyTag.stringByReplacingMatches(
                in: inner,
                range: NSRange(inner.startIndex..., in: inner),
                withTemplate: ""
            )

            // Step C: Decode HTML entities so that e.g. &lt; becomes < in the fenced block.
            // This runs AFTER tag-stripping so that entity-encoded angle brackets are not
            // re-interpreted as tag delimiters.
            inner = decodeEntities(inner)

            let fenced = "\n```\n\(inner)\n```\n"
            result = result.replacingOccurrences(of: placeholder, with: fenced)
        }
        return result
    }

    // MARK: - Non-content region stripping

    /// Strips non-content regions entirely (tag + inner content).
    ///
    /// Removes: `<script>`, `<style>`, `<head>`, `<noscript>`, `<svg>`, and HTML comments.
    /// Each opening-tag pattern uses a lookahead `(?=[\s>/])` so that e.g. `<head…>` does
    /// NOT match `<header>`.
    private static func stripRegions(_ s: String) -> String {
        var result = s
        let regionREs = [reRegionScript, reRegionStyle, reRegionHead, reRegionNoscript, reRegionSvg]
        for re in regionREs {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Strip HTML comments
        let range = NSRange(result.startIndex..., in: result)
        result = reHtmlComment.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        return result
    }

    // MARK: - Main region selection

    /// Picks the main content region from the stripped HTML.
    ///
    /// Preference order: `<article>` > `<main>` > `<body>` > whole string.
    private static func pickMainRegion(_ s: String) -> String {
        let candidates = [(reInnerArticle, "article"), (reInnerMain, "main"), (reInnerBody, "body")]
        for (re, _) in candidates {
            if let inner = extractInner(re: re, from: s) {
                return inner
            }
        }
        return s
    }

    /// Extracts the inner HTML of the first match for `re` (capture group 1).
    private static func extractInner(re: NSRegularExpression, from s: String) -> String? {
        let range = NSRange(s.startIndex..., in: s)
        guard let match = re.firstMatch(in: s, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: s) else {
            return nil
        }
        return String(s[captureRange])
    }

    // MARK: - Block-tag conversion (pre-blockquote: <br> and paragraph tags only)

    /// Converts `<br>` tags, opening block tags, and closing paragraph/block tags to newlines.
    ///
    /// Opening block tags (`<p>`, `<div>`, `<section>`, etc.) insert a blank-line separator
    /// *before* the tag's content, mirroring the blank line that closing tags already insert
    /// *after* it.  This ensures that `Intro<p>First paragraph</p>` produces separate
    /// paragraphs rather than running together.
    ///
    /// This pass runs BEFORE blockquote conversion so that multi-paragraph blockquote
    /// inner content is already split into lines when each line is prefixed with `> `.
    private static func convertBrAndParagraphTags(_ s: String) -> String {
        var result = s

        // <br> / <br/> / <br /> → newline
        result = reBr.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "\n"
        )

        // Opening block tags → blank line separator before content
        result = reBlockOpeners.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "\n\n"
        )

        // Closing block tags → blank line (single combined pass)
        result = reBlockClosers.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "\n\n"
        )

        return result
    }

    /// Converts `<blockquote>…</blockquote>` blocks so each non-empty inner line is prefixed
    /// with `> `.
    ///
    /// This method is called AFTER `convertBrAndParagraphTags`, so inner `<p>` closers and
    /// `<br>` tags have already been turned into newlines. Multi-paragraph blockquotes are
    /// therefore handled correctly: each paragraph produces its own `> `-prefixed line(s).
    ///
    /// **Limitation:** Nested blockquotes are not supported. Nested `<blockquote>` tags will
    /// be matched by the lazy regex in outer-first order; the inner tags will be stripped as
    /// ordinary HTML in a later pass rather than producing additional `> ` levels.
    private static func convertBlockquotes(_ s: String) -> String {
        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = reBlockquote.matches(in: s, range: fullRange)

        guard !matches.isEmpty else { return s }

        var result = ""
        var lastEnd = s.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: s) else { continue }

            result += s[lastEnd..<matchRange.lowerBound]

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

            lastEnd = matchRange.upperBound
        }

        result += s[lastEnd...]
        return result
    }

    // MARK: - Remaining block-tag conversion

    /// Converts remaining block-level HTML tags to their Markdown equivalents.
    ///
    /// Handles headings and list items. (`<br>` and closing block tags are already
    /// handled by `convertBrAndParagraphTags`; `<pre>` blocks are protected by
    /// `protectPreBlocks` and restored at the end.)
    private static func convertBlockTags(_ s: String) -> String {
        var result = s

        // <li>…</li> → "- …"
        result = reLi.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "\n- $1"
        )

        // Headings h1–h6: opening tag → Markdown prefix.
        for (openRE, closeRE, marker) in headingPatterns {
            result = openRE.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "\n\n\(marker) "
            )
            result = closeRE.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "\n\n"
            )
        }

        return result
    }

    // MARK: - Inline-tag conversion

    /// Converts inline HTML tags to their Markdown equivalents.
    ///
    /// Handles links, bold, italic, and inline code.
    private static func convertInlineTags(_ s: String) -> String {
        var result = s

        // <a href="URL">TEXT</a> → [TEXT](URL)
        result = convertLinks(result)

        // <strong>…</strong> and <b>…</b> → **…**
        for re in reBold {
            result = re.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "**$1**"
            )
        }

        // <em>…</em> and <i>…</i> → *…*
        for re in reItalic {
            result = re.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "*$1*"
            )
        }

        // <code>…</code> → `…` (inline only; <pre><code> is protected by placeholders)
        result = reInlineCode.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "`$1`"
        )

        return result
    }

    /// Converts `<a href="…">TEXT</a>` to `[TEXT](URL)` Markdown link syntax.
    ///
    /// Accepts double-quoted, single-quoted, and unquoted `href` values, with optional
    /// whitespace around the `=` sign (e.g. `href = "url"` and `href=url` are both valid).
    ///
    /// Capture groups in `reLinkWithHref`:
    /// - Group 1: double-quoted URL
    /// - Group 2: single-quoted URL
    /// - Group 3: unquoted URL
    /// - Group 4: link text
    ///
    /// Falls back to plain TEXT when no `href` attribute is present.
    private static func convertLinks(_ s: String) -> String {
        let nsString = s as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = reLinkWithHref.matches(in: s, range: fullRange)

        var result = ""
        var lastEnd = s.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: s) else { continue }
            result += s[lastEnd..<matchRange.lowerBound]

            // URL: whichever of groups 1 (double-quoted), 2 (single-quoted), 3 (unquoted) matched.
            let url: String = {
                for groupIndex in 1...3 {
                    if match.numberOfRanges > groupIndex {
                        let r = match.range(at: groupIndex)
                        if r.location != NSNotFound, let range = Range(r, in: s) {
                            return String(s[range])
                        }
                    }
                }
                return ""
            }()

            // Text is capture group 4.
            let text: String
            if match.numberOfRanges > 4, let textRange = Range(match.range(at: 4), in: s) {
                text = String(s[textRange])
            } else {
                text = ""
            }

            result += url.isEmpty ? text : "[\(text)](\(url))"
            lastEnd = matchRange.upperBound
        }

        result += s[lastEnd...]

        // Remaining <a> tags without href → strip tags, keep inner text
        result = reLinkNoHref.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )

        return result
    }

    // MARK: - Tag stripping

    /// Strips all remaining HTML tags from the string.
    private static func stripRemainingTags(_ s: String) -> String {
        return reAnyTag.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: ""
        )
    }

    // MARK: - Entity decoding

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
        result = replaceNumericEntities(result, regex: reDecimalEntity, radix: 10)

        // Hexadecimal numeric entities: &#xHH; or &#XHH;
        result = replaceNumericEntities(result, regex: reHexEntity, radix: 16)

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

    // MARK: - Whitespace normalisation

    /// Normalises whitespace in the extracted Markdown text.
    ///
    /// - Collapses runs of spaces and tabs on the same line to a single space.
    /// - Trims trailing spaces from each line.
    /// - Collapses three or more consecutive blank lines to exactly two newlines (one blank line).
    /// - Trims leading and trailing whitespace from the final result.
    ///
    /// Note: This pass operates on the main text only. `<pre>` block content is protected by
    /// placeholder tokens and is therefore not affected.
    private static func normaliseWhitespace(_ s: String) -> String {
        var result = s

        // Collapse runs of horizontal whitespace (spaces/tabs) to a single space.
        result = reHorizontalWS.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: " "
        )

        // Trim trailing spaces on each line.
        result = reTrailingSpaceOnLine.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )

        // Collapse 3+ consecutive newlines to exactly 2.
        result = reMultiNewline.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "\n\n"
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
