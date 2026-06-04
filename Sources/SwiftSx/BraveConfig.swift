/// Configuration for the Brave Search backend.
public struct BraveConfig: Codable, Sendable, Equatable {
    /// Brave Search API key.
    /// Overridden at runtime by the `BRAVE_API_KEY` environment variable.
    public var apiKey: String

    public init(apiKey: String = "") {
        self.apiKey = apiKey
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }

    // MARK: - Decodable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}
