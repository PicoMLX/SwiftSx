import Foundation
import Testing
@testable import SwiftSx

// MARK: - SearchResultLength

@Suite struct SearchResultLengthTests {

    @Test func decodesDouble() throws {
        let json = "42.0"
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(SearchResultLength.self, from: data)
        #expect(value == .seconds(42.0))
    }

    @Test func decodesString() throws {
        let json = #""3:21""#
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(SearchResultLength.self, from: data)
        #expect(value == .text("3:21"))
    }

    @Test func encodesSeconds() throws {
        let length = SearchResultLength.seconds(99.5)
        let data = try JSONEncoder().encode(length)
        let decoded = try JSONDecoder().decode(Double.self, from: data)
        #expect(decoded == 99.5)
    }

    @Test func encodesText() throws {
        let length = SearchResultLength.text("1h 2m")
        let data = try JSONEncoder().encode(length)
        let decoded = try JSONDecoder().decode(String.self, from: data)
        #expect(decoded == "1h 2m")
    }

    @Test func roundTripSeconds() throws {
        let original = SearchResultLength.seconds(180.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SearchResultLength.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTripText() throws {
        let original = SearchResultLength.text("3:21")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SearchResultLength.self, from: data)
        #expect(decoded == original)
    }

    @Test func throwsOnInvalidType() throws {
        // A JSON object is neither Double nor String.
        let json = #"{"bad": true}"#
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SearchResultLength.self, from: data)
        }
    }
}

// MARK: - SearchResult

@Suite struct SearchResultTests {

    // MARK: Full JSON round-trip

    private let fullJSON = """
        {
          "title": "Swift Concurrency",
          "url": "https://swift.org/concurrency",
          "content": "Swift's structured concurrency model.",
          "engine": "brave",
          "engines": ["brave", "searxng"],
          "category": "general",
          "template": "general.html",
          "publishedDate": "2024-03-01",
          "author": "Swift Team",
          "length": 120.0,
          "source": "swift.org",
          "resolution": "1920x1080",
          "img_src": "https://swift.org/logo.png",
          "address": {"street": "1 Apple Park", "city": "Cupertino"},
          "longitude": -122.0090,
          "latitude": 37.3346,
          "journal": "WWDC Proceedings",
          "publisher": "Apple",
          "magnetlink": "magnet:?xt=urn:btih:abc",
          "seed": 42,
          "leech": 7,
          "filesize": "4.2 MB",
          "size": "4200000",
          "metadata": "some metadata"
        }
        """

    @Test func decodesFullJSON() throws {
        let data = Data(fullJSON.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)

        #expect(result.title == "Swift Concurrency")
        #expect(result.url == "https://swift.org/concurrency")
        #expect(result.content == "Swift's structured concurrency model.")
        #expect(result.engine == "brave")
        #expect(result.engines == ["brave", "searxng"])
        #expect(result.category == "general")
        #expect(result.template == "general.html")
        #expect(result.publishedDate == "2024-03-01")
        #expect(result.author == "Swift Team")
        #expect(result.length == .seconds(120.0))
        #expect(result.source == "swift.org")
        #expect(result.resolution == "1920x1080")
        #expect(result.imgSrc == "https://swift.org/logo.png")
        #expect(result.address == ["street": "1 Apple Park", "city": "Cupertino"])
        #expect(result.longitude == -122.0090)
        #expect(result.latitude == 37.3346)
        #expect(result.journal == "WWDC Proceedings")
        #expect(result.publisher == "Apple")
        #expect(result.magnetlink == "magnet:?xt=urn:btih:abc")
        #expect(result.seed == 42)
        #expect(result.leech == 7)
        #expect(result.filesize == "4.2 MB")
        #expect(result.size == "4200000")
        #expect(result.metadata == "some metadata")
    }

    @Test func decodesLengthAsString() throws {
        let json = #"{"length": "3:21"}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(result.length == .text("3:21"))
    }

    @Test func decodesImgSrcMapping() throws {
        // `img_src` in JSON must map to `imgSrc` in Swift.
        let json = #"{"img_src": "https://example.com/img.jpg"}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(result.imgSrc == "https://example.com/img.jpg")
    }

    @Test func decodesAddressTable() throws {
        let json = #"{"address": {"city": "London", "country": "UK"}}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(result.address == ["city": "London", "country": "UK"])
    }

    // MARK: Lenient decoding

    @Test func decodesEmptyObjectToDefaults() throws {
        let data = Data("{}".utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)

        #expect(result.title == "")
        #expect(result.url == "")
        #expect(result.content == "")
        #expect(result.engine == "")
        #expect(result.engines == [])
        #expect(result.category == "")
        #expect(result.template == "")
        #expect(result.publishedDate == "")
        #expect(result.author == "")
        #expect(result.length == nil)
        #expect(result.source == "")
        #expect(result.resolution == "")
        #expect(result.imgSrc == "")
        #expect(result.address == nil)
        #expect(result.longitude == 0)
        #expect(result.latitude == 0)
        #expect(result.journal == "")
        #expect(result.publisher == "")
        #expect(result.magnetlink == "")
        #expect(result.seed == 0)
        #expect(result.leech == 0)
        #expect(result.filesize == "")
        #expect(result.size == "")
        #expect(result.metadata == "")
    }

    @Test func leniencyIgnoresUnknownField() throws {
        // An extra unknown field must not fail the decode.
        let json = #"{"title": "Hello", "unknown_field_xyz": {"nested": 99}, "url": "https://example.com"}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(result.title == "Hello")
        #expect(result.url == "https://example.com")
    }

    @Test func leniencyIgnoresMistypedField() throws {
        // A mistyped field (number where string expected) must not abort the whole decode;
        // the bad field falls back to its default.
        let json = #"{"title": 12345, "url": "https://example.com"}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        // `title` falls back to "" because 12345 is not a String.
        #expect(result.title == "")
        // Other valid fields decode normally.
        #expect(result.url == "https://example.com")
    }

    @Test func leniencySkipsNonStringAddressValues() throws {
        // Non-string values within `address` are silently skipped.
        let json = #"{"address": {"city": "Tokyo", "count": 3, "active": true}}"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        // Only the String value should survive.
        #expect(result.address == ["city": "Tokyo"])
    }

    @Test func addressNilWhenAbsent() throws {
        let data = Data("{}".utf8)
        let result = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(result.address == nil)
    }

    @Test func leniencyHandlesArrayOfResultsWithOneBadField() throws {
        // A bad field in one result must not abort decoding of the whole array.
        let json = """
            [
              {"title": 999, "url": "https://a.example.com"},
              {"title": "Good", "url": "https://b.example.com"}
            ]
            """
        let data = Data(json.utf8)
        let results = try JSONDecoder().decode([SearchResult].self, from: data)
        #expect(results.count == 2)
        #expect(results[0].title == "")
        #expect(results[0].url == "https://a.example.com")
        #expect(results[1].title == "Good")
    }

    // MARK: Encoding

    @Test func encodesImgSrcToCorrectKey() throws {
        let result = SearchResult(imgSrc: "https://example.com/img.png")
        let data = try JSONEncoder().encode(result)
        // Decode as heterogeneous JSON: the encoded object also contains arrays
        // and numbers (engines, longitude, seed, …), so [String: String] would
        // type-mismatch before we could assert.
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])
        // The encoded key must be `img_src`, not `imgSrc`.
        #expect(json["img_src"] as? String == "https://example.com/img.png")
        #expect(json["imgSrc"] == nil)
    }

    @Test func roundTripFullResult() throws {
        let original = SearchResult(
            title: "Round Trip",
            url: "https://rt.example.com",
            content: "content",
            engine: "exa",
            engines: ["exa"],
            category: "general",
            template: "general.html",
            publishedDate: "2024-01-01",
            author: "Author",
            length: .seconds(60.0),
            source: "rt.example.com",
            resolution: "",
            imgSrc: "https://rt.example.com/img.png",
            address: ["city": "Paris"],
            longitude: 2.3522,
            latitude: 48.8566,
            journal: "",
            publisher: "",
            magnetlink: "",
            seed: 0,
            leech: 0,
            filesize: "",
            size: "",
            metadata: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SearchResult.self, from: data)
        #expect(decoded == original)
    }

    // MARK: Memberwise init defaults

    @Test func memberwiseInitDefaults() {
        let result = SearchResult()
        #expect(result.title == "")
        #expect(result.url == "")
        #expect(result.content == "")
        #expect(result.engine == "")
        #expect(result.engines == [])
        #expect(result.category == "")
        #expect(result.template == "")
        #expect(result.publishedDate == "")
        #expect(result.author == "")
        #expect(result.length == nil)
        #expect(result.source == "")
        #expect(result.resolution == "")
        #expect(result.imgSrc == "")
        #expect(result.address == nil)
        #expect(result.longitude == 0)
        #expect(result.latitude == 0)
        #expect(result.journal == "")
        #expect(result.publisher == "")
        #expect(result.magnetlink == "")
        #expect(result.seed == 0)
        #expect(result.leech == 0)
        #expect(result.filesize == "")
        #expect(result.size == "")
        #expect(result.metadata == "")
    }
}
