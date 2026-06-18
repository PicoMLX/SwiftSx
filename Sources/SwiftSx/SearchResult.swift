/// A single search result returned by a backend.
///
/// JSON keys match the upstream `byteowlz/sx` result schema so that
/// `--json` output is compatible with the Go implementation. Every field
/// is optional in the decoder (missing or mistyped fields fall back to their
/// defaults), so one malformed field in an array of results can never abort
/// the entire decode.
public struct SearchResult: Codable, Sendable, Equatable {

    // MARK: - Fields

    /// Page title.
    public var title: String
    /// Canonical URL of the result.
    public var url: String
    /// Short content snippet / description.
    public var content: String

    /// Name of the single engine that returned this result (SearXNG field).
    public var engine: String
    /// All engines that returned this result (SearXNG merged field).
    public var engines: [String]

    /// SearXNG result category (e.g. `"general"`, `"news"`, `"images"`).
    public var category: String
    /// SearXNG template hint (e.g. `"general.html"`, `"images.html"`).
    public var template: String

    /// ISO 8601 publication date string, if available.
    public var publishedDate: String
    /// Author name, if available.
    public var author: String

    /// Duration of a media result (seconds or human-readable text), if available.
    public var length: SearchResultLength?

    /// Source domain or publication name.
    public var source: String
    /// Resolution string for image/video results (e.g. `"1920×1080"`).
    public var resolution: String
    /// Image source URL for image results.
    public var imgSrc: String

    /// Structured address fields (e.g. for map results), if available.
    ///
    /// Non-string values within the object are silently skipped so that an
    /// unexpected numeric sub-field cannot break the decode.
    public var address: [String: JSONValue]?

    /// Longitude coordinate for map results.
    public var longitude: Double
    /// Latitude coordinate for map results.
    public var latitude: Double

    /// Academic journal name.
    public var journal: String
    /// Academic publisher name.
    public var publisher: String

    /// BitTorrent magnet link.
    public var magnetlink: String
    /// Number of seeders for a torrent result.
    public var seed: Int
    /// Number of leechers for a torrent result.
    public var leech: Int

    /// Human-readable file size (e.g. `"4.2 MB"`).
    public var filesize: String
    /// Alternative size string (used by some backends).
    public var size: String
    /// Additional metadata string.
    public var metadata: String

    // MARK: - Memberwise init (all defaults)

    public init(
        title: String = "",
        url: String = "",
        content: String = "",
        engine: String = "",
        engines: [String] = [],
        category: String = "",
        template: String = "",
        publishedDate: String = "",
        author: String = "",
        length: SearchResultLength? = nil,
        source: String = "",
        resolution: String = "",
        imgSrc: String = "",
        address: [String: JSONValue]? = nil,
        longitude: Double = 0,
        latitude: Double = 0,
        journal: String = "",
        publisher: String = "",
        magnetlink: String = "",
        seed: Int = 0,
        leech: Int = 0,
        filesize: String = "",
        size: String = "",
        metadata: String = ""
    ) {
        self.title       = title
        self.url         = url
        self.content     = content
        self.engine      = engine
        self.engines     = engines
        self.category    = category
        self.template    = template
        self.publishedDate = publishedDate
        self.author      = author
        self.length      = length
        self.source      = source
        self.resolution  = resolution
        self.imgSrc      = imgSrc
        self.address     = address
        self.longitude   = longitude
        self.latitude    = latitude
        self.journal     = journal
        self.publisher   = publisher
        self.magnetlink  = magnetlink
        self.seed        = seed
        self.leech       = leech
        self.filesize    = filesize
        self.size        = size
        self.metadata    = metadata
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case engine
        case engines
        case category
        case template
        case publishedDate  = "publishedDate"
        case author
        case length
        case source
        case resolution
        case imgSrc         = "img_src"
        case address
        case longitude
        case latitude
        case journal
        case publisher
        case magnetlink
        case seed
        case leech
        case filesize
        case size
        case metadata
    }

    // MARK: - Decodable (lenient: every field optional → default)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        title       = (try? c.decodeIfPresent(String.self,              forKey: .title))       ?? ""
        url         = (try? c.decodeIfPresent(String.self,              forKey: .url))         ?? ""
        content     = (try? c.decodeIfPresent(String.self,              forKey: .content))     ?? ""
        engine      = (try? c.decodeIfPresent(String.self,              forKey: .engine))      ?? ""
        engines     = (try? c.decodeIfPresent([String].self,            forKey: .engines))     ?? []
        category    = (try? c.decodeIfPresent(String.self,              forKey: .category))    ?? ""
        template    = (try? c.decodeIfPresent(String.self,              forKey: .template))    ?? ""
        publishedDate = (try? c.decodeIfPresent(String.self,            forKey: .publishedDate)) ?? ""
        author      = (try? c.decodeIfPresent(String.self,              forKey: .author))      ?? ""
        length      = try? c.decodeIfPresent(SearchResultLength.self,   forKey: .length)
        source      = (try? c.decodeIfPresent(String.self,              forKey: .source))      ?? ""
        resolution  = (try? c.decodeIfPresent(String.self,              forKey: .resolution))  ?? ""
        imgSrc      = (try? c.decodeIfPresent(String.self,              forKey: .imgSrc))      ?? ""
        longitude   = (try? c.decodeIfPresent(Double.self,              forKey: .longitude))   ?? 0
        latitude    = (try? c.decodeIfPresent(Double.self,              forKey: .latitude))    ?? 0
        journal     = (try? c.decodeIfPresent(String.self,              forKey: .journal))     ?? ""
        publisher   = (try? c.decodeIfPresent(String.self,              forKey: .publisher))   ?? ""
        magnetlink  = (try? c.decodeIfPresent(String.self,              forKey: .magnetlink))  ?? ""
        seed        = (try? c.decodeIfPresent(Int.self,                 forKey: .seed))        ?? 0
        leech       = (try? c.decodeIfPresent(Int.self,                 forKey: .leech))       ?? 0
        filesize    = (try? c.decodeIfPresent(String.self,              forKey: .filesize))    ?? ""
        size        = (try? c.decodeIfPresent(String.self,              forKey: .size))        ?? ""
        metadata    = (try? c.decodeIfPresent(String.self,              forKey: .metadata))    ?? ""

        // address: decode a keyed container, preserving each scalar sub-field's
        // JSON type as a JSONValue (upstream's `map[string]interface{}` keeps the
        // original types). Nested objects/arrays fail to decode and are skipped;
        // explicit nulls are skipped too, matching the prior behaviour.
        if c.contains(.address), let nested = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .address) {
            var dict = [String: JSONValue]()
            for key in nested.allKeys {
                if let value = try? nested.decode(JSONValue.self, forKey: key), value != .null {
                    dict[key.stringValue] = value
                }
            }
            address = dict
        } else {
            address = nil
        }
    }
}

// MARK: - AnyCodingKey (private helper for dynamic address decoding)

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}
