import Foundation
import Testing
@testable import SwiftSx

@Suite struct JSONValueTests {

    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: Decoding preserves type

    @Test func decodesString() throws { #expect(try decode(#""hi""#) == .string("hi")) }
    @Test func decodesInt() throws { #expect(try decode("42") == .int(42)) }
    @Test func decodesLargeInt() throws { #expect(try decode("9000000000") == .int(9_000_000_000)) }
    @Test func decodesDouble() throws { #expect(try decode("3.5") == .double(3.5)) }
    @Test func decodesBool() throws { #expect(try decode("true") == .bool(true)) }
    @Test func decodesNull() throws { #expect(try decode("null") == .null) }

    @Test func nestedObjectFailsToDecode() {
        // Only scalars are supported; an object must throw (callers skip it).
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"k":1}"#.utf8))
        }
    }

    // MARK: Encoding keeps types (numbers/bools unquoted)

    @Test func encodesNumberUnquoted() throws {
        let s = String(decoding: try JSONEncoder().encode(["i": JSONValue.int(3)]), as: UTF8.self)
        #expect(s.contains(#""i":3"#))      // not "i":"3"
    }

    @Test func encodesBoolUnquoted() throws {
        let s = String(decoding: try JSONEncoder().encode(["b": JSONValue.bool(true)]), as: UTF8.self)
        #expect(s.contains(#""b":true"#))
    }

    @Test func roundTripsThroughCodable() throws {
        let original: [String: JSONValue] =
            ["city": "Paris", "count": 3, "active": true, "score": 1.5, "void": .null]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(decoded == original)
    }

    // MARK: Literal conformances

    @Test func literalsProduceTypedCases() {
        let s: JSONValue = "x"
        let i: JSONValue = 7
        let b: JSONValue = false
        let d: JSONValue = 2.5
        #expect(s == .string("x"))
        #expect(i == .int(7))
        #expect(b == .bool(false))
        #expect(d == .double(2.5))
    }

    // MARK: Foundation bridging (for the --json renderer)

    @Test func foundationValueMapsScalars() {
        #expect(JSONValue.string("x").foundationValue as? String == "x")
        #expect(JSONValue.int(3).foundationValue as? Int64 == 3)
        #expect(JSONValue.double(1.5).foundationValue as? Double == 1.5)
        #expect(JSONValue.bool(true).foundationValue as? Bool == true)
        #expect(JSONValue.null.foundationValue is NSNull)
    }
}
