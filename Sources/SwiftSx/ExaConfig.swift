/// Configuration for the Exa Search backend.
public struct ExaConfig: Codable, Sendable, Equatable {
    /// Transport mode: `"auto"` (default — REST API, falling back to MCP),
    /// `"api"`, or `"mcp"`. (This selects the transport, not an Exa search type;
    /// upstream `sx` does not expose a neural/keyword search-type option.)
    public var mode: String
    /// Exa API key.
    /// Overridden at runtime by the `EXA_API_KEY` environment variable.
    public var apiKey: String
    /// Optional MCP server URL for Exa (used instead of the REST API when set).
    public var mcpURL: String
    /// MCP tool name to call on the MCP server.
    public var mcpTool: String
    /// Number of results to return.
    public var numResults: Int

    public init(
        mode: String = "auto",
        apiKey: String = "",
        mcpURL: String = "",
        mcpTool: String = "exa-web-search",
        numResults: Int = 10
    ) {
        self.mode       = mode
        self.apiKey     = apiKey
        self.mcpURL     = mcpURL
        self.mcpTool    = mcpTool
        self.numResults = numResults
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case mode       = "mode"
        case apiKey     = "api_key"
        case mcpURL     = "mcp_url"
        case mcpTool    = "mcp_tool"
        case numResults = "num_results"
    }

    // MARK: - Decodable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode       = try container.decodeIfPresent(String.self, forKey: .mode)       ?? "auto"
        apiKey     = try container.decodeIfPresent(String.self, forKey: .apiKey)     ?? ""
        mcpURL     = try container.decodeIfPresent(String.self, forKey: .mcpURL)     ?? ""
        mcpTool    = try container.decodeIfPresent(String.self, forKey: .mcpTool)    ?? "exa-web-search"
        numResults = try container.decodeIfPresent(Int.self,    forKey: .numResults) ?? 10
    }
}
