import Foundation
import Testing
@testable import SwiftSx

// MARK: -

/// Tests for `HTMLExtractor.extract(_:)`.
///
/// Each test exercises one concern in the extraction pipeline.  Assertions use
/// `.contains(_:)` for sub-string checks and exact equality only where the test
/// controls the full output (e.g. the entity / plain-text edge-case suite).
@Suite struct HTMLExtractorTests {

    // MARK: - Non-content region stripping

    @Test func scriptContentsAreRemoved() {
        let html = "<html><body><p>Hello</p><script>alert('evil');</script></body></html>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("alert"))
        #expect(!result.contains("evil"))
        #expect(result.contains("Hello"))
    }

    @Test func styleContentsAreRemoved() {
        let html = "<html><head><style>body { color: red; }</style></head><body><p>World</p></body></html>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("color"))
        #expect(!result.contains("red"))
        #expect(result.contains("World"))
    }

    @Test func headContentsAreRemoved() {
        let html = "<html><head><title>Page Title</title><meta charset='utf-8'></head><body><p>Content</p></body></html>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("Page Title"))
        #expect(result.contains("Content"))
    }

    @Test func noscriptContentsAreRemoved() {
        let html = "<body><noscript>Enable JS</noscript><p>Main</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("Enable JS"))
        #expect(result.contains("Main"))
    }

    @Test func svgContentsAreRemoved() {
        let html = "<body><svg><circle cx='50' cy='50' r='40'/></svg><p>Text</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("circle"))
        #expect(!result.contains("cx="))
        #expect(result.contains("Text"))
    }

    @Test func htmlCommentsAreRemoved() {
        let html = "<body><!-- This is a comment --><p>Visible</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("This is a comment"))
        #expect(result.contains("Visible"))
    }

    @Test func multilineCommentsAreRemoved() {
        let html = "<body><!--\n  multi\n  line\n  comment\n--><p>Keep</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("multi"))
        #expect(!result.contains("line"))
        #expect(result.contains("Keep"))
    }

    // MARK: - Tag-prefix collision fix (Issue 1)

    /// `<head…>…</head>` must be stripped but `<header>…</header>` content must NOT be stripped.
    @Test func headTagStrippedButHeaderContentPreserved() {
        let html = "<html><head><title>Meta</title></head><body><header><p>Site Header Content</p></header><p>Body</p></body></html>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("Meta"))
        #expect(result.contains("Site Header Content"))
        #expect(result.contains("Body"))
    }

    /// `<main…>…</main>` should be found as the main region, but a `<main-content>` custom
    /// element must not match the `<main>` extractor.
    @Test func mainTagDoesNotMatchMainContentCustomElement() {
        // No <article> or <main> present — falls back to <body>.
        let html = "<body><main-content><p>Custom</p></main-content><p>Normal</p></body>"
        let result = HTMLExtractor.extract(html)
        // The body fallback should surface "Normal"; "Custom" may also appear.
        // The key assertion: we don't accidentally strip <main-content> while looking for <main>.
        #expect(result.contains("Normal"))
    }

    // MARK: - Main region selection

    @Test func articleContentIsPreferredOverSurroundingChrome() {
        let html = """
        <html>
          <body>
            <nav>Navigation Menu</nav>
            <header>Site Header</header>
            <article>
              <h1>Article Title</h1>
              <p>Article body text.</p>
            </article>
            <footer>Site Footer</footer>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Article Title"))
        #expect(result.contains("Article body text"))
        // Chrome outside <article> must not appear
        #expect(!result.contains("Navigation Menu"))
        #expect(!result.contains("Site Header"))
        #expect(!result.contains("Site Footer"))
    }

    @Test func mainFallbackWhenNoArticle() {
        let html = """
        <html>
          <body>
            <nav>Nav</nav>
            <main>
              <p>Main content here.</p>
            </main>
            <aside>Sidebar</aside>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Main content here"))
        #expect(!result.contains("Sidebar"))
        #expect(!result.contains("Nav"))
    }

    @Test func bodyFallbackWhenNoArticleOrMain() {
        let html = """
        <html>
          <body>
            <p>Body content.</p>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Body content"))
    }

    @Test func wholeStringFallbackWhenNoSemanticContainer() {
        let html = "<p>Fallback content.</p>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Fallback content"))
    }

    // MARK: - Heading conversion

    @Test func h1ConvertsToMarkdownHeading() {
        let html = "<body><h1>Title One</h1><p>Para.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("# Title One"))
    }

    @Test func h2ConvertsToMarkdownHeading() {
        let html = "<body><h2>Section</h2><p>Para.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("## Section"))
    }

    @Test func h3ConvertsToMarkdownHeading() {
        let html = "<body><h3>Sub-section</h3></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("### Sub-section"))
    }

    @Test func h4ThroughH6Convert() {
        let html = "<body><h4>H4</h4><h5>H5</h5><h6>H6</h6></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("#### H4"))
        #expect(result.contains("##### H5"))
        #expect(result.contains("###### H6"))
    }

    // MARK: - Link conversion

    @Test func anchorWithHrefConvertsToMarkdownLink() {
        let html = "<body><a href=\"https://x.com\">X</a></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("[X](https://x.com)"))
    }

    @Test func anchorWithSingleQuotedHrefConvertsToMarkdownLink() {
        let html = "<body><a href='https://example.com'>Example</a></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("[Example](https://example.com)"))
    }

    @Test func anchorWithNoHrefKeepsText() {
        let html = "<body><a name='anchor'>Anchor Text</a></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Anchor Text"))
        #expect(!result.contains("]("))
    }

    // MARK: - List item conversion

    @Test func listItemsConvertToDashPrefix() {
        let html = "<body><ul><li>First</li><li>Second</li><li>Third</li></ul></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("- First"))
        #expect(result.contains("- Second"))
        #expect(result.contains("- Third"))
    }

    @Test func orderedListItemsConvertToDashPrefix() {
        let html = "<body><ol><li>Alpha</li><li>Beta</li></ol></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("- Alpha"))
        #expect(result.contains("- Beta"))
    }

    // MARK: - Inline formatting

    @Test func strongConvertsToDoubleStar() {
        let html = "<body><p>Some <strong>bold</strong> text.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("**bold**"))
    }

    @Test func bConvertsToDoubleStar() {
        let html = "<body><p>Some <b>bold</b> text.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("**bold**"))
    }

    @Test func emConvertsToSingleStar() {
        let html = "<body><p>Some <em>italic</em> text.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("*italic*"))
    }

    @Test func iConvertsToSingleStar() {
        let html = "<body><p>Some <i>italic</i> text.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("*italic*"))
    }

    @Test func inlineCodeConvertsToBacktick() {
        let html = "<body><p>Use <code>print()</code> to log.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("`print()`"))
    }

    // MARK: - Pre / code-block fidelity (Issue 2)

    @Test func preConvertsToFencedCodeBlock() {
        let html = "<body><pre>let x = 1\nlet y = 2</pre></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("```"))
        #expect(result.contains("let x = 1"))
        #expect(result.contains("let y = 2"))
    }

    /// Internal indentation inside `<pre>` must be preserved verbatim.
    @Test func prePreservesInternalIndentation() {
        let html = "<body><pre>  indented\n    more indented</pre></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("  indented"))
        #expect(result.contains("    more indented"))
    }

    /// `<pre><code>…</code></pre>` must produce a clean fenced block, not inline backticks
    /// wrapped inside the fence.
    @Test func preCodeDoesNotProduceInnerBackticks() {
        let html = "<body><pre><code>let x = 1</code></pre></body>"
        let result = HTMLExtractor.extract(html)
        // Should contain a fenced block with the raw source
        #expect(result.contains("```"))
        #expect(result.contains("let x = 1"))
        // The inner content must NOT be wrapped in inline backticks inside the fence
        #expect(!result.contains("`let x = 1`"))
    }

    /// Inline `<code>` in regular text must still produce backticks.
    @Test func inlineCodeOutsidePreStillUsesBackticks() {
        let html = "<body><p>Call <code>foo()</code> here.</p><pre>bar()</pre></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("`foo()`"))
        #expect(result.contains("bar()"))
    }

    // MARK: - Blockquote (Issue 4)

    @Test func blockquoteLinesPrefixedWithAngle() {
        let html = "<body><blockquote>Quoted text here.</blockquote></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("> Quoted text here."))
    }

    /// A multi-paragraph blockquote must have BOTH paragraphs prefixed with `> `.
    @Test func multiParagraphBlockquotePrefixesBothParagraphs() {
        let html = "<body><blockquote><p>One</p><p>Two</p></blockquote></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("> One"))
        #expect(result.contains("> Two"))
    }

    @Test func brConvertsToNewline() {
        let html = "<body>Line one<br>Line two<br/>Line three</body>"
        let result = HTMLExtractor.extract(html)
        let lines = result.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(lines.contains("Line one"))
        #expect(lines.contains("Line two"))
        #expect(lines.contains("Line three"))
    }

    // MARK: - Entity decoding

    @Test func commonEntitiesDecode() {
        let html = "<body><p>&amp; &lt; &gt; &quot; &#39; &nbsp;</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("&"))
        #expect(result.contains("<"))
        #expect(result.contains(">"))
        #expect(result.contains("\""))
        #expect(result.contains("'"))
        // &nbsp; becomes a regular space, which then gets collapsed — just verify no raw entity remains
        #expect(!result.contains("&nbsp;"))
        #expect(!result.contains("&amp;"))
        #expect(!result.contains("&lt;"))
        #expect(!result.contains("&gt;"))
        #expect(!result.contains("&quot;"))
        #expect(!result.contains("&#39;"))
    }

    @Test func ampDecodedLastPreventsDoubleUnescaping() {
        // &amp;lt; should become &lt; (the literal two characters), not <
        let html = "<body><p>&amp;lt;</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("&lt;"))
        #expect(!result.contains("&amp;lt;"))
    }

    @Test func decimalNumericEntityDecodes() {
        // &#65; is 'A'
        let html = "<body><p>&#65;BC</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("ABC"))
    }

    @Test func hexNumericEntityDecodes() {
        // &#x41; is 'A'
        let html = "<body><p>&#x41;BC</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("ABC"))
    }

    @Test func aposEntityDecodes() {
        let html = "<body><p>It&apos;s fine.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("It's fine."))
    }

    // MARK: - Whitespace normalisation

    @Test func noRunsOfThreeOrMoreNewlines() {
        let html = "<body><p>A</p><p>B</p><p>C</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("\n\n\n"))
    }

    @Test func noLeadingOrTrailingWhitespace() {
        let html = "   <body><p>  Spaced  </p></body>   "
        let result = HTMLExtractor.extract(html)
        #expect(result == result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func noTrailingSpacesOnLines() {
        let html = "<body><p>Hello   </p><p>World   </p></body>"
        let result = HTMLExtractor.extract(html)
        let lines = result.components(separatedBy: "\n")
        for line in lines {
            // Capture for the assertion comment — avoids capturing var in @autoclosure.
            let lineSnapshot = line
            #expect(!lineSnapshot.hasSuffix(" "), "Line ends with a trailing space")
        }
    }

    @Test func horizontalWhitespaceCollapsed() {
        let html = "<body><p>Too    many    spaces</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("  "))
        #expect(result.contains("Too many spaces"))
    }

    // MARK: - Determinism

    @Test func deterministicOutput() {
        let html = """
        <html>
          <head><title>Test</title></head>
          <body>
            <article>
              <h1>Determinism Test</h1>
              <p>This <strong>test</strong> verifies <em>consistent</em> output.</p>
              <a href="https://example.com">Link</a>
            </article>
          </body>
        </html>
        """
        let first = HTMLExtractor.extract(html)
        let second = HTMLExtractor.extract(html)
        #expect(first == second)
    }

    // MARK: - Robustness / edge cases

    @Test func emptyStringReturnsEmpty() {
        let result = HTMLExtractor.extract("")
        #expect(result.isEmpty)
    }

    @Test func plaintextWithNoTagsReturnsText() {
        let input = "Hello, world!"
        let result = HTMLExtractor.extract(input)
        #expect(result == "Hello, world!")
    }

    @Test func onlyWhitespaceInput() {
        let result = HTMLExtractor.extract("   \n\t\n  ")
        #expect(result.isEmpty)
    }

    @Test func malformedHtmlDoesNotCrash() {
        let html = "<body><p>Unclosed tag <strong>bold text<p>Another paragraph</body>"
        // Should not crash; result is a best-effort extraction
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("bold text") || result.contains("Another paragraph"))
    }

    @Test func deeplyNestedHtmlDoesNotCrash() {
        let inner = String(repeating: "<div>", count: 50) + "Deep content" + String(repeating: "</div>", count: 50)
        let html = "<body>\(inner)</body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Deep content"))
    }

    @Test func selfClosingTagsHandledGracefully() {
        let html = "<body><img src='cat.png' alt='cat'/><p>After image</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("After image"))
    }

    @Test func scriptWithAttributesIsRemoved() {
        let html = "<body><script type=\"text/javascript\" src=\"app.js\">var x = 1;</script><p>Clean</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("var x"))
        #expect(result.contains("Clean"))
    }

    @Test func caseInsensitiveTagMatching() {
        let html = "<BODY><H1>Title</H1><P>Content</P></BODY>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("# Title"))
        #expect(result.contains("Content"))
    }

    @Test func realWorldLikeSnippet() {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="UTF-8">
            <title>Blog Post</title>
            <style>body { font-family: sans-serif; }</style>
          </head>
          <body>
            <nav>
              <a href="/">Home</a> | <a href="/about">About</a>
            </nav>
            <article>
              <h1>Getting Started with Swift</h1>
              <p>Swift is a <strong>powerful</strong> and <em>expressive</em> language.</p>
              <h2>Installation</h2>
              <ul>
                <li>Download Xcode from the App Store</li>
                <li>Install Swift toolchain</li>
              </ul>
              <p>Learn more at <a href="https://swift.org">swift.org</a>.</p>
              <!-- Author: Jane Doe -->
            </article>
            <footer>Copyright &copy; 2024</footer>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)

        // Navigation must not appear (outside <article>)
        #expect(!result.contains("Home"))
        #expect(!result.contains("About"))
        #expect(!result.contains("Copyright"))

        // Article content must appear correctly formatted
        #expect(result.contains("# Getting Started with Swift"))
        #expect(result.contains("## Installation"))
        #expect(result.contains("**powerful**"))
        #expect(result.contains("*expressive*"))
        #expect(result.contains("- Download Xcode from the App Store"))
        #expect(result.contains("- Install Swift toolchain"))
        #expect(result.contains("[swift.org](https://swift.org)"))

        // Comment must not appear
        #expect(!result.contains("Author: Jane Doe"))

        // Style must not appear
        #expect(!result.contains("font-family"))
    }

    // MARK: - Fix 1: Syntax-highlight tags stripped inside <pre> blocks

    /// `<pre><code>` blocks containing syntax-highlight `<span>` markup must produce a fenced
    /// code block with only the plain text content — no literal `<span …>` markup should remain.
    /// HTML entities inside the block (e.g. `&lt;`) must still decode to their characters.
    @Test func syntaxHighlightSpansStrippedInsidePre() {
        // Simulates output from a syntax highlighter: <span class="k">let</span>
        let html = #"<body><pre><code><span class="k">let</span> x = <span class="m">1</span></code></pre></body>"#
        let result = HTMLExtractor.extract(html)
        // Fenced code block must be present
        #expect(result.contains("```"))
        // Plain text must be extracted
        #expect(result.contains("let x = 1"))
        // No residual span markup
        #expect(!result.contains("<span"))
        #expect(!result.contains("</span>"))
        // Entities inside pre still decode correctly
        let htmlWithEntities = #"<body><pre><code><span class="k">&lt;Node&gt;</span></code></pre></body>"#
        let result2 = HTMLExtractor.extract(htmlWithEntities)
        #expect(result2.contains("<Node>"))
        #expect(!result2.contains("&lt;"))
    }

    // MARK: - Fix 2: Tag-boundary lookahead accepts newlines in HTML attributes

    /// Real-world HTML wraps attributes across lines, e.g. `<article\n  class="post">`.
    /// The extractor must still recognise `<article>` as the main region and exclude nav/footer
    /// chrome even when the opening tag spans multiple lines.
    @Test func multilineAttributesOnContainerTagMatchesMainRegion() {
        let html = """
        <html>
          <body>
            <nav>Chrome Nav</nav>
            <article
              class="post"
              id="main-article">
              <p>Article content here.</p>
            </article>
            <footer>Chrome Footer</footer>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)
        // Article content must be extracted
        #expect(result.contains("Article content here"))
        // Chrome outside the article must not appear
        #expect(!result.contains("Chrome Nav"))
        #expect(!result.contains("Chrome Footer"))
    }

    // MARK: - Fix 3: Opening block tags introduce a paragraph separator

    /// Text immediately before an opening `<p>` tag must be separated from the paragraph
    /// content by a blank line, not run together as a single line.
    @Test func openingPTagSeparatesAdjacentText() {
        let html = "<body>Intro text<p>First paragraph</p><p>Second paragraph</p></body>"
        let result = HTMLExtractor.extract(html)
        // All three chunks of text must appear
        #expect(result.contains("Intro text"))
        #expect(result.contains("First paragraph"))
        #expect(result.contains("Second paragraph"))
        // "Intro text" must NOT be immediately followed by "First paragraph" on the same line
        #expect(!result.contains("Intro textFirst paragraph"))
        // Verify they are actually on different paragraphs (separated by at least one newline)
        let introRange = result.range(of: "Intro text")
        let firstRange = result.range(of: "First paragraph")
        if let ir = introRange, let fr = firstRange {
            let between = String(result[ir.upperBound..<fr.lowerBound])
            #expect(between.contains("\n"))
        }
    }

    /// A `<div>` immediately after inline text must likewise introduce a separator.
    @Test func openingDivTagSeparatesAdjacentText() {
        let html = "<body>Lead text<div>Block content</div></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Lead text"))
        #expect(result.contains("Block content"))
        #expect(!result.contains("Lead textBlock content"))
    }

    // MARK: - Fix 4: Relaxed href attribute syntax

    /// `href` with whitespace around the `=` sign must produce a Markdown link.
    @Test func hrefWithSpacesAroundEqualsProducesMarkdownLink() {
        let html = #"<body><a href = "https://example.com">Example</a></body>"#
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("[Example](https://example.com)"))
    }

    /// An unquoted `href` value must produce a Markdown link.
    @Test func unquotedHrefProducesMarkdownLink() {
        let html = "<body><a href=https://swift.org>Swift</a></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("[Swift](https://swift.org)"))
    }

    // MARK: - Review item 1: href must be a standalone attribute

    /// An anchor whose only `href`-like attribute is `data-href` must NOT become a Markdown
    /// link — `href` has to be its own attribute, not a suffix of another one.
    @Test func dataHrefIsNotTreatedAsLink() {
        let html = #"<body><a data-href="/tracking">Continue</a></body>"#
        let result = HTMLExtractor.extract(html)
        // Plain text is kept…
        #expect(result.contains("Continue"))
        // …but no Markdown link syntax is produced.
        #expect(!result.contains("]("))
        #expect(!result.contains("/tracking"))
    }

    /// A real `href` sitting next to a `data-href` must still produce a link to the real URL.
    @Test func realHrefAlongsideDataHrefStillLinks() {
        let html = #"<body><a data-href="/track" href="https://example.com">Go</a></body>"#
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("[Go](https://example.com)"))
        #expect(!result.contains("/track"))
    }

    /// Regression guard: the previously supported href forms (double/single quoted, spaces
    /// around `=`, unquoted) must all keep working after the standalone-attribute tightening.
    @Test func standaloneHrefStillMatchesAllSupportedForms() {
        #expect(HTMLExtractor.extract(#"<body><a href="https://a.com">A</a></body>"#)
            .contains("[A](https://a.com)"))
        #expect(HTMLExtractor.extract("<body><a href='https://b.com'>B</a></body>")
            .contains("[B](https://b.com)"))
        #expect(HTMLExtractor.extract(#"<body><a href = "https://c.com">C</a></body>"#)
            .contains("[C](https://c.com)"))
        #expect(HTMLExtractor.extract("<body><a href=https://d.com>D</a></body>")
            .contains("[D](https://d.com)"))
        // href after another attribute must still match.
        #expect(HTMLExtractor.extract(#"<body><a class="x" href="https://e.com">E</a></body>"#)
            .contains("[E](https://e.com)"))
    }

    // MARK: - Review item 2: <br> with attributes is a line break

    /// `<br class="…">` must still act as a line break, not be silently dropped.
    @Test func brWithAttributesActsAsLineBreak() {
        let html = #"<body>One<br class="mobile-break">Two</body>"#
        let result = HTMLExtractor.extract(html)
        // The two halves must not run together…
        #expect(!result.contains("OneTwo"))
        // …and must land on separate lines.
        let lines = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(lines.contains("One"))
        #expect(lines.contains("Two"))
    }

    /// `<br>` with attributes must not match a different tag that merely starts with `br`.
    @Test func brMatcherDoesNotMatchOtherTags() {
        // A hypothetical `<br…>`-prefixed custom element should not introduce a line break by
        // virtue of the `<br>` rule. `<break>` content stays on a single line.
        let html = "<body>Alpha<break>Beta</break></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("AlphaBeta"))
    }

    // MARK: - Review item 3: table cells are separated

    /// Adjacent table cells must be separated rather than concatenated.
    @Test func tableCellsAreSeparated() {
        let html = "<body><table><tr><td>A</td><td>B</td></tr></table></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("A B"))
        #expect(!result.contains("AB"))
    }

    /// Cells must stay separated even when `</td>`/`</tr>` end tags are omitted.
    @Test func tableCellsSeparatedWithOmittedEndTags() {
        let html = "<body><table><tr><td>A<td>B</tr></table></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("A B"))
        #expect(!result.contains("AB"))
    }

    /// Separate table rows must land on separate lines.
    @Test func tableRowsAreSeparatedByNewlines() {
        let html = "<body><table><tr><td>R1</td></tr><tr><td>R2</td></tr></table></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("R1"))
        #expect(result.contains("R2"))
        #expect(!result.contains("R1R2"))
        #expect(!result.contains("R1 R2"))
        let lines = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(lines.contains("R1"))
        #expect(lines.contains("R2"))
    }

    // MARK: - Review item 4: bullets preserved when </li> is omitted

    /// HTML allows omitting `</li>`; bullets must still be produced for each item.
    @Test func listItemsWithoutClosingTagsKeepBullets() {
        let html = "<body><ul><li>One<li>Two</ul></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("- One"))
        #expect(result.contains("- Two"))
        #expect(!result.contains("OneTwo"))
    }

    /// Ordered lists with omitted `</li>` must also keep bullets.
    @Test func orderedListItemsWithoutClosingTagsKeepBullets() {
        let html = "<body><ol><li>Alpha<li>Beta</ol></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("- Alpha"))
        #expect(result.contains("- Beta"))
        #expect(!result.contains("AlphaBeta"))
    }

    /// A mix of explicit and omitted `</li>` end tags must be handled.
    @Test func listItemsMixedClosingTagsKeepBullets() {
        let html = "<body><ul><li>One</li><li>Two<li>Three</ul></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("- One"))
        #expect(result.contains("- Two"))
        #expect(result.contains("- Three"))
    }

    // MARK: - Review item 5: list items inside blockquotes stay quoted

    /// A list inside a blockquote must have its bullets prefixed with `> ` like the rest of the
    /// quote, not rendered outside it.
    @Test func listItemsInsideBlockquoteStayQuoted() {
        let html = "<body><blockquote><ul><li>One</li></ul></blockquote></body>"
        let result = HTMLExtractor.extract(html)
        // The bullet must be quoted.
        #expect(result.contains("> - One"))
        // It must NOT appear as an unquoted bullet on its own line.
        let hasUnquotedBullet = result
            .components(separatedBy: "\n")
            .contains { $0.hasPrefix("- One") }
        #expect(!hasUnquotedBullet)
    }

    /// A multi-item list inside a blockquote keeps every bullet quoted.
    @Test func multiItemListInsideBlockquoteStaysQuoted() {
        let html = "<body><blockquote><ul><li>One</li><li>Two</li></ul></blockquote></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("> - One"))
        #expect(result.contains("> - Two"))
    }

    // MARK: - Review item 6: nested containers preserve the outer tail

    /// When `<article>` elements are nested, the outer article's tail content (after the inner
    /// `</article>`) must not be discarded.
    @Test func nestedArticlesPreserveOuterTail() {
        let html = "<article><article><h1>Inner</h1></article><p>Outer tail</p></article>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Inner"))
        #expect(result.contains("Outer tail"))
    }

    /// Nested `<main>` elements must likewise preserve the outer tail.
    @Test func nestedMainPreservesOuterTail() {
        let html = "<main><main><h1>Inner</h1></main><p>Outer tail</p></main>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Inner"))
        #expect(result.contains("Outer tail"))
    }

    /// Regression guard: a single, non-nested `<article>` must still be isolated from
    /// surrounding chrome (the nesting heuristic must not change the common case).
    @Test func singleArticleStillExcludesChromeAfterNestingFix() {
        let html = """
        <html>
          <body>
            <nav>Nav Chrome</nav>
            <article>
              <h1>Title</h1>
              <p>Body text.</p>
            </article>
            <footer>Footer Chrome</footer>
          </body>
        </html>
        """
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("# Title"))
        #expect(result.contains("Body text"))
        #expect(!result.contains("Nav Chrome"))
        #expect(!result.contains("Footer Chrome"))
    }

    // MARK: - Review item: literal angle brackets in prose

    /// A literal `<` followed by whitespace/digits is text, not markup, so a comparison
    /// like `2 < 3 and 4 > 1` must survive tag stripping intact.
    @Test func literalLessThanInProseIsPreserved() {
        let html = "<body><p>For all n, 2 < 3 and 4 > 1 holds.</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("2 < 3 and 4 > 1"))
    }

    /// Real tags are still stripped even with the stricter tag-start requirement.
    @Test func realTagsStillStrippedAlongsideLiteralLessThan() {
        let html = "<body><p>a <span>b</span> c < d</p></body>"
        let result = HTMLExtractor.extract(html)
        #expect(!result.contains("<span>"))
        #expect(result.contains("c < d"))
    }

    // MARK: - Review item: code fence sizing around embedded backticks

    /// A `<pre>` block whose content contains a Markdown fence must be wrapped in a
    /// longer fence so the embedded ``` cannot close the generated code block early.
    @Test func preBlockWithEmbeddedFenceUsesLongerFence() {
        let html = "<body><pre>```\ncode\n```</pre></body>"
        let result = HTMLExtractor.extract(html)
        // Outer fence must be at least 4 backticks (longer than the embedded run of 3).
        #expect(result.contains("````"))
    }

    // MARK: - Review item: nested lists keep both bullets

    /// A nested list must not collapse parent and child into one run. Indentation is
    /// flattened (a best-effort-extractor limitation), but both bullets are preserved.
    @Test func nestedListsKeepBothBullets() {
        let html = "<body><ul><li>Parent<ul><li>Child</li></ul></li></ul></body>"
        let result = HTMLExtractor.extract(html)
        #expect(result.contains("Parent"))
        #expect(result.contains("Child"))
        #expect(!result.contains("ParentChild"))
    }
}
