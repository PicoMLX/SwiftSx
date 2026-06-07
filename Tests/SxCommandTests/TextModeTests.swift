import Testing
import SwiftSx
@testable import SxCommand

@Suite struct TextModeTests {

    @Test func parsesTextFlag() throws {
        #expect(try Sx.parse(["q", "--text"]).text)
        #expect(!(try Sx.parse(["q"]).text))
    }

    @Test func pageContentsExtractsMarkdownWhenAsText() {
        let contents = Sx.pageContents(["<body><h1>Hello</h1><p>World</p></body>"], asText: true)
        #expect(contents.count == 1)
        let md = contents[0]
        #expect(md?.contains("Hello") == true)
        #expect(md?.contains("World") == true)
        #expect(md?.contains("<h1>") == false)   // tags are stripped
    }

    @Test func pageContentsKeepsRawWhenNotAsText() {
        let raw = "<body><h1>Hello</h1></body>"
        #expect(Sx.pageContents([raw], asText: false)[0] == raw)
    }

    @Test func pageContentsPreservesNil() {
        #expect(Sx.pageContents([nil], asText: true)[0] == nil)
        #expect(Sx.pageContents([nil], asText: false)[0] == nil)
    }

    @Test func textExtractionDecodesEntities() {
        // The content mapping runs HTMLExtractor, which decodes entities.
        let contents = Sx.pageContents(["<p>Body &amp; soul</p>"], asText: true)
        #expect(contents[0]?.contains("Body & soul") == true)
    }
}
