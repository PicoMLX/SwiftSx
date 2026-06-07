/// Top-level configuration for SwiftSx, loaded from `$XDG_CONFIG_HOME/sx/config.toml`
/// (default `~/.config/sx/config.toml`).
///
/// All properties default to sensible values so `Config()` yields a usable
/// default configuration even when no config file is present. Missing keys in
/// the TOML file are substituted with these same defaults via a custom
/// `init(from:)`.
///
/// Environment variables (e.g. `BRAVE_API_KEY`) override the corresponding
/// config-file values at load time — see ``applyingEnvironmentOverrides(_:)``.
public struct Config: Codable, Sendable, Equatable {
    // MARK: - Schema

    /// Optional JSON-schema reference (`$schema` key in TOML).
    public var schema: String?

    // MARK: - Engine selection

    /// Primary search engine. Default: `"searxng"`.
    public var engine: String
    /// Ordered list of fallback engines tried when the primary fails.
    public var fallbackEngines: [String]

    // MARK: - SearXNG

    /// Single SearXNG instance URL (convenience; combined with `searxngURLs`).
    public var searxngURL: String
    /// All SearXNG instance URLs (populated and deduped at load time).
    public var searxngURLs: [String]
    /// Multi-instance strategy: `"ordered"` (default) or `"parallel-fastest"`.
    public var searxngStrategy: String
    /// HTTP Basic-auth username for SearXNG.
    public var searxngUsername: String
    /// HTTP Basic-auth password for SearXNG.
    public var searxngPassword: String

    // MARK: - Query tuning

    /// Number of results to return per search. Default: `10`.
    public var resultCount: Int
    /// Search categories (e.g. `["general", "news"]`).
    public var categories: [String]
    /// Safe-search level: `"strict"` (default), `"moderate"`, or `"off"`.
    public var safeSearch: String
    /// Engines to request from SearXNG (passes through to the API).
    public var engines: [String]
    /// Whether to expand results (SearXNG `pageno > 1` style expansion).
    public var expand: Bool
    /// Language/locale code (e.g. `"en-US"`). Empty = server default.
    public var language: String

    // MARK: - HTTP

    /// HTTP method used for SearXNG queries: `"GET"` (default) or `"POST"`.
    public var httpMethod: String
    /// Network timeout in seconds. Default: `30.0`.
    public var timeout: Double
    /// Disable TLS certificate verification (not recommended).
    public var noVerifySSL: Bool
    /// Omit the `User-Agent` header from requests.
    public var noUserAgent: Bool

    // MARK: - Output / UX

    /// Suppress ANSI colour codes in output.
    public var noColor: Bool
    /// Shell command / URL handler used to open result URLs (unused in agent mode).
    public var urlHandler: String
    /// Enable verbose debug output.
    public var debug: Bool
    /// Default output format: `""`, `"json"`, `"links"`, etc.
    public var defaultOutput: String

    // MARK: - History

    /// Whether to record search history. Default: `true`.
    public var historyEnabled: Bool
    /// Maximum number of history entries to keep. Default: `100`.
    public var maxHistory: Int

    // MARK: - Backend configs

    /// Brave Search backend configuration.
    public var enginesBrave: BraveConfig
    /// Tavily Search backend configuration.
    public var enginesTavily: TavilyConfig
    /// Exa Search backend configuration.
    public var enginesExa: ExaConfig
    /// Jina AI Search backend configuration.
    public var enginesJina: JinaConfig

    // MARK: - Memberwise init (all defaults)

    public init(
        schema: String? = nil,
        engine: String = "searxng",
        fallbackEngines: [String] = [],
        searxngURL: String = "",
        searxngURLs: [String] = [],
        searxngStrategy: String = "ordered",
        searxngUsername: String = "",
        searxngPassword: String = "",
        resultCount: Int = 10,
        categories: [String] = [],
        safeSearch: String = "strict",
        engines: [String] = [],
        expand: Bool = false,
        language: String = "",
        httpMethod: String = "GET",
        timeout: Double = 30.0,
        noVerifySSL: Bool = false,
        noUserAgent: Bool = false,
        noColor: Bool = false,
        urlHandler: String = "",
        debug: Bool = false,
        defaultOutput: String = "",
        historyEnabled: Bool = true,
        maxHistory: Int = 100,
        enginesBrave: BraveConfig = BraveConfig(),
        enginesTavily: TavilyConfig = TavilyConfig(),
        enginesExa: ExaConfig = ExaConfig(),
        enginesJina: JinaConfig = JinaConfig()
    ) {
        self.schema          = schema
        self.engine          = engine
        self.fallbackEngines = fallbackEngines
        self.searxngURL      = searxngURL
        self.searxngURLs     = searxngURLs
        self.searxngStrategy = searxngStrategy
        self.searxngUsername = searxngUsername
        self.searxngPassword = searxngPassword
        self.resultCount     = resultCount
        self.categories      = categories
        self.safeSearch      = safeSearch
        self.engines         = engines
        self.expand          = expand
        self.language        = language
        self.httpMethod      = httpMethod
        self.timeout         = timeout
        self.noVerifySSL     = noVerifySSL
        self.noUserAgent     = noUserAgent
        self.noColor         = noColor
        self.urlHandler      = urlHandler
        self.debug           = debug
        self.defaultOutput   = defaultOutput
        self.historyEnabled  = historyEnabled
        self.maxHistory      = maxHistory
        self.enginesBrave    = enginesBrave
        self.enginesTavily   = enginesTavily
        self.enginesExa      = enginesExa
        self.enginesJina     = enginesJina
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case schema          = "$schema"
        case engine          = "engine"
        case fallbackEngines = "fallback_engines"
        case searxngURL      = "searxng_url"
        case searxngURLs     = "searxng_urls"
        case searxngStrategy = "searxng_strategy"
        case searxngUsername = "searxng_username"
        case searxngPassword = "searxng_password"
        case resultCount     = "result_count"
        case categories      = "categories"
        case safeSearch      = "safe_search"
        case engines         = "engines"
        case expand          = "expand"
        case language        = "language"
        case httpMethod      = "http_method"
        case timeout         = "timeout"
        case noVerifySSL     = "no_verify_ssl"
        case noUserAgent     = "no_user_agent"
        case noColor         = "no_color"
        case urlHandler      = "url_handler"
        case debug           = "debug"
        case defaultOutput   = "default_output"
        case historyEnabled  = "history_enabled"
        case maxHistory      = "max_history"
        case enginesBrave    = "engines_brave"
        case enginesTavily   = "engines_tavily"
        case enginesExa      = "engines_exa"
        case enginesJina     = "engines_jina"
    }

    // MARK: - Decodable (all keys optional; missing → default)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema          = try c.decodeIfPresent(String.self,       forKey: .schema)
        engine          = try c.decodeIfPresent(String.self,       forKey: .engine)          ?? "searxng"
        fallbackEngines = try c.decodeIfPresent([String].self,     forKey: .fallbackEngines) ?? []
        searxngURL      = try c.decodeIfPresent(String.self,       forKey: .searxngURL)      ?? ""
        searxngURLs     = try c.decodeIfPresent([String].self,     forKey: .searxngURLs)     ?? []
        searxngStrategy = try c.decodeIfPresent(String.self,       forKey: .searxngStrategy) ?? "ordered"
        searxngUsername = try c.decodeIfPresent(String.self,       forKey: .searxngUsername) ?? ""
        searxngPassword = try c.decodeIfPresent(String.self,       forKey: .searxngPassword) ?? ""
        resultCount     = try c.decodeIfPresent(Int.self,          forKey: .resultCount)     ?? 10
        categories      = try c.decodeIfPresent([String].self,     forKey: .categories)      ?? []
        safeSearch      = try c.decodeIfPresent(String.self,       forKey: .safeSearch)      ?? "strict"
        engines         = try c.decodeIfPresent([String].self,     forKey: .engines)         ?? []
        expand          = try c.decodeIfPresent(Bool.self,         forKey: .expand)          ?? false
        language        = try c.decodeIfPresent(String.self,       forKey: .language)        ?? ""
        httpMethod      = try c.decodeIfPresent(String.self,       forKey: .httpMethod)      ?? "GET"
        timeout         = try c.decodeIfPresent(Double.self,       forKey: .timeout)         ?? 30.0
        noVerifySSL     = try c.decodeIfPresent(Bool.self,         forKey: .noVerifySSL)     ?? false
        noUserAgent     = try c.decodeIfPresent(Bool.self,         forKey: .noUserAgent)     ?? false
        noColor         = try c.decodeIfPresent(Bool.self,         forKey: .noColor)         ?? false
        urlHandler      = try c.decodeIfPresent(String.self,       forKey: .urlHandler)      ?? ""
        debug           = try c.decodeIfPresent(Bool.self,         forKey: .debug)           ?? false
        defaultOutput   = try c.decodeIfPresent(String.self,       forKey: .defaultOutput)   ?? ""
        historyEnabled  = try c.decodeIfPresent(Bool.self,         forKey: .historyEnabled)  ?? true
        maxHistory      = try c.decodeIfPresent(Int.self,          forKey: .maxHistory)      ?? 100
        enginesBrave    = try c.decodeIfPresent(BraveConfig.self,  forKey: .enginesBrave)    ?? BraveConfig()
        enginesTavily   = try c.decodeIfPresent(TavilyConfig.self, forKey: .enginesTavily)   ?? TavilyConfig()
        enginesExa      = try c.decodeIfPresent(ExaConfig.self,    forKey: .enginesExa)      ?? ExaConfig()
        enginesJina     = try c.decodeIfPresent(JinaConfig.self,   forKey: .enginesJina)     ?? JinaConfig()
    }
}
