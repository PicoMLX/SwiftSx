/// The length of a search result, which may be expressed either as a numeric
/// duration in seconds (e.g. for video results) or as a human-readable string
/// (e.g. `"3:21"`).
///
/// SearXNG backends encode this field inconsistently; the lenient decoder tries
/// `Double` first, then `String`, and throws only if neither fits.
public enum SearchResultLength: Codable, Sendable, Equatable {
    /// A duration in seconds.
    case seconds(Double)
    /// A human-readable length string (e.g. `"3:21"`, `"1h 2m"`).
    case text(String)

    // MARK: - Decodable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .seconds(value)
        } else if let value = try? container.decode(String.self) {
            self = .text(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "SearchResultLength expects a Double or String"
            )
        }
    }

    // MARK: - Encodable

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .seconds(let value):
            try container.encode(value)
        case .text(let value):
            try container.encode(value)
        }
    }
}
