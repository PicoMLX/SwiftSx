/// Configuration for the Jina AI Search backend.
public struct JinaConfig: Codable, Sendable, Equatable {
    /// Jina API key.
    /// Overridden at runtime by the `JINA_API_KEY` environment variable.
    public var apiKey: String
    /// Whether keyless (unauthenticated) access is allowed.
    public var allowKeyless: Bool
    /// Base URL for the Jina reader/search endpoint.
    public var baseURL: String

    public init(
        apiKey: String = "",
        allowKeyless: Bool = true,
        baseURL: String = "https://s.jina.ai"
    ) {
        self.apiKey       = apiKey
        self.allowKeyless = allowKeyless
        self.baseURL      = baseURL
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case apiKey       = "api_key"
        case allowKeyless = "allow_keyless"
        case baseURL      = "base_url"
    }

    // MARK: - Decodable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey       = try container.decodeIfPresent(String.self, forKey: .apiKey)       ?? ""
        allowKeyless = try container.decodeIfPresent(Bool.self,   forKey: .allowKeyless) ?? true
        baseURL      = try container.decodeIfPresent(String.self, forKey: .baseURL)      ?? "https://s.jina.ai"
    }
}
