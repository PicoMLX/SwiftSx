/// Configuration for the Tavily Search backend.
public struct TavilyConfig: Codable, Sendable, Equatable {
    /// Tavily API key.
    /// Overridden at runtime by the `TAVILY_API_KEY` environment variable.
    public var apiKey: String
    /// Search depth: `"basic"` (default) or `"advanced"`.
    public var searchDepth: String
    /// Whether to include raw page content in results.
    public var includeRawContent: Bool
    /// Whether to include an AI-generated answer in results.
    public var includeAnswer: Bool

    public init(
        apiKey: String = "",
        searchDepth: String = "basic",
        includeRawContent: Bool = false,
        includeAnswer: Bool = false
    ) {
        self.apiKey = apiKey
        self.searchDepth = searchDepth
        self.includeRawContent = includeRawContent
        self.includeAnswer = includeAnswer
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case apiKey             = "api_key"
        case searchDepth        = "search_depth"
        case includeRawContent  = "include_raw_content"
        case includeAnswer      = "include_answer"
    }

    // MARK: - Decodable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey            = try container.decodeIfPresent(String.self, forKey: .apiKey)            ?? ""
        searchDepth       = try container.decodeIfPresent(String.self, forKey: .searchDepth)       ?? "basic"
        includeRawContent = try container.decodeIfPresent(Bool.self,   forKey: .includeRawContent) ?? false
        includeAnswer     = try container.decodeIfPresent(Bool.self,   forKey: .includeAnswer)     ?? false
    }
}
