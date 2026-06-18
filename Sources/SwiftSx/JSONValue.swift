import Foundation

/// A JSON scalar value that preserves its original type.
///
/// Used by ``SearchResult/address`` so heterogeneous sub-fields (mirroring
/// upstream `sx`'s `map[string]interface{}`) keep their JSON type through
/// decode → `--json` re-encode: a number stays a number and a bool stays a
/// bool, rather than being flattened to a string.
///
/// Only scalars are modelled (`string` / `int` / `double` / `bool` / `null`);
/// nested objects and arrays are not represented and are skipped at decode time.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Order matters: null first, then bool before int (a JSON bool must not
        // be read as a number) and int before double (an integer must stay an
        // integer, not become a Double).
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "JSONValue supports only scalar JSON (string/number/bool/null)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    /// A Foundation value suitable for `JSONSerialization` (used by the `--json`
    /// renderer): `String` / `Int64` / `Double` / `Bool` / `NSNull`.
    public var foundationValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        case .double(let d): return d
        case .bool(let b):   return b
        case .null:          return NSNull()
        }
    }
}

// MARK: - Literal conformances (ergonomic construction & test fixtures)

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
