import Testing
@testable import SwiftSx

// MARK: - TOML Decoding

@Suite struct ConfigTOMLDecodingTests {

    // A TOML sample that populates every top-level key and all nested tables.
    private let fullTOML = """
        engine = "brave"
        fallback_engines = ["searxng", "tavily"]
        searxng_url = "https://sx1.example.com"
        searxng_urls = ["https://sx2.example.com"]
        searxng_strategy = "fastest"
        searxng_username = "user"
        searxng_password = "pass"
        result_count = 5
        categories = ["news", "general"]
        safe_search = "moderate"
        engines = ["google", "bing"]
        expand = true
        language = "en-US"
        http_method = "POST"
        timeout = 60.0
        no_verify_ssl = true
        no_user_agent = true
        no_color = true
        url_handler = "open"
        debug = true
        default_output = "json"
        history_enabled = false
        max_history = 50

        [engines_brave]
        api_key = "brave-key-123"

        [engines_tavily]
        api_key = "tavily-key-456"
        search_depth = "advanced"
        include_raw_content = true
        include_answer = true

        [engines_exa]
        mode = "neural"
        api_key = "exa-key-789"
        mcp_url = "https://mcp.example.com"
        mcp_tool = "my-exa-tool"
        num_results = 20

        [engines_jina]
        api_key = "jina-key-abc"
        allow_keyless = false
        base_url = "https://custom.jina.ai"
        """

    @Test func decodesFullTOML() throws {
        let config = try Config.decode(fromTOML: fullTOML)

        // Top-level fields
        #expect(config.engine == "brave")
        #expect(config.fallbackEngines == ["searxng", "tavily"])
        #expect(config.searxngURL == "https://sx1.example.com")
        #expect(config.searxngURLs == ["https://sx2.example.com"])
        #expect(config.searxngStrategy == "fastest")
        #expect(config.searxngUsername == "user")
        #expect(config.searxngPassword == "pass")
        #expect(config.resultCount == 5)
        #expect(config.categories == ["news", "general"])
        #expect(config.safeSearch == "moderate")
        #expect(config.engines == ["google", "bing"])
        #expect(config.expand == true)
        #expect(config.language == "en-US")
        #expect(config.httpMethod == "POST")
        #expect(config.timeout == 60.0)
        #expect(config.noVerifySSL == true)
        #expect(config.noUserAgent == true)
        #expect(config.noColor == true)
        #expect(config.urlHandler == "open")
        #expect(config.debug == true)
        #expect(config.defaultOutput == "json")
        #expect(config.historyEnabled == false)
        #expect(config.maxHistory == 50)

        // Nested: BraveConfig
        #expect(config.enginesBrave.apiKey == "brave-key-123")

        // Nested: TavilyConfig
        #expect(config.enginesTavily.apiKey == "tavily-key-456")
        #expect(config.enginesTavily.searchDepth == "advanced")
        #expect(config.enginesTavily.includeRawContent == true)
        #expect(config.enginesTavily.includeAnswer == true)

        // Nested: ExaConfig
        #expect(config.enginesExa.mode == "neural")
        #expect(config.enginesExa.apiKey == "exa-key-789")
        #expect(config.enginesExa.mcpURL == "https://mcp.example.com")
        #expect(config.enginesExa.mcpTool == "my-exa-tool")
        #expect(config.enginesExa.numResults == 20)

        // Nested: JinaConfig
        #expect(config.enginesJina.apiKey == "jina-key-abc")
        #expect(config.enginesJina.allowKeyless == false)
        #expect(config.enginesJina.baseURL == "https://custom.jina.ai")
    }

    @Test func decodesEmptyStringToDefaults() throws {
        let config = try Config.decode(fromTOML: "")

        // Spot-check that important defaults are present.
        #expect(config.engine == "searxng")
        #expect(config.fallbackEngines == [])
        #expect(config.resultCount == 10)
        #expect(config.safeSearch == "strict")
        #expect(config.historyEnabled == true)
        #expect(config.maxHistory == 100)
        #expect(config.timeout == 30.0)
        #expect(config.httpMethod == "GET")
        #expect(config.expand == false)
        #expect(config.noVerifySSL == false)
        #expect(config.enginesJina.baseURL == "https://s.jina.ai")
        #expect(config.enginesBrave.apiKey == "")
        #expect(config.enginesTavily.searchDepth == "basic")
        #expect(config.enginesExa.mode == "auto")
        #expect(config.enginesExa.mcpTool == "exa-web-search")

        // Decoding empty TOML should equal the zero-init Config.
        #expect(config == Config())
    }

    @Test func decodesPartialTOML() throws {
        let partial = """
            engine = "exa"
            result_count = 3
            """
        let config = try Config.decode(fromTOML: partial)

        // Explicitly set fields
        #expect(config.engine == "exa")
        #expect(config.resultCount == 3)

        // Unmentioned fields default
        #expect(config.fallbackEngines == [])
        #expect(config.safeSearch == "strict")
        #expect(config.historyEnabled == true)
        #expect(config.enginesJina.baseURL == "https://s.jina.ai")
        #expect(config.enginesBrave.apiKey == "")
    }

    @Test func throwsOnInvalidTOML() throws {
        let bad = "engine = [not valid toml"
        #expect(throws: SxError.self) {
            try Config.decode(fromTOML: bad)
        }
    }
}

// MARK: - Environment overrides

@Suite struct ConfigEnvironmentTests {

    @Test func envOverridesApiKeys() {
        let base = Config()
        let env: [String: String] = [
            "BRAVE_API_KEY":  "brave-env",
            "TAVILY_API_KEY": "tavily-env",
            "EXA_API_KEY":    "exa-env",
            "JINA_API_KEY":   "jina-env",
        ]
        let result = base.applyingEnvironmentOverrides(env)

        #expect(result.enginesBrave.apiKey   == "brave-env")
        #expect(result.enginesTavily.apiKey  == "tavily-env")
        #expect(result.enginesExa.apiKey     == "exa-env")
        #expect(result.enginesJina.apiKey    == "jina-env")
    }

    @Test func emptyEnvValueDoesNotOverride() {
        var base = Config()
        base.enginesBrave.apiKey   = "file-brave"
        base.enginesTavily.apiKey  = "file-tavily"
        base.enginesExa.apiKey     = "file-exa"
        base.enginesJina.apiKey    = "file-jina"

        let env: [String: String] = [
            "BRAVE_API_KEY":  "",
            "TAVILY_API_KEY": "",
            "EXA_API_KEY":    "",
            "JINA_API_KEY":   "",
        ]
        let result = base.applyingEnvironmentOverrides(env)

        // Empty env vars must not overwrite file-sourced values.
        #expect(result.enginesBrave.apiKey   == "file-brave")
        #expect(result.enginesTavily.apiKey  == "file-tavily")
        #expect(result.enginesExa.apiKey     == "file-exa")
        #expect(result.enginesJina.apiKey    == "file-jina")
    }

    @Test func absentEnvKeyDoesNotOverride() {
        var base = Config()
        base.enginesBrave.apiKey = "from-file"

        let result = base.applyingEnvironmentOverrides([:])

        #expect(result.enginesBrave.apiKey == "from-file")
    }

    @Test func partialEnvOverridesOnlyPresent() {
        var base = Config()
        base.enginesBrave.apiKey  = "from-file-brave"
        base.enginesTavily.apiKey = "from-file-tavily"

        let env: [String: String] = [
            "BRAVE_API_KEY": "env-brave",
            // TAVILY_API_KEY absent
        ]
        let result = base.applyingEnvironmentOverrides(env)

        #expect(result.enginesBrave.apiKey   == "env-brave")
        #expect(result.enginesTavily.apiKey  == "from-file-tavily")
    }
}

// MARK: - Normalization

@Suite struct ConfigNormalizationTests {

    @Test func emptyStrategyDefaultsToOrdered() {
        var config = Config()
        config.searxngStrategy = ""
        let result = config.normalized()
        #expect(result.searxngStrategy == "ordered")
    }

    @Test func nonEmptyStrategyPreserved() {
        var config = Config()
        config.searxngStrategy = "fastest"
        let result = config.normalized()
        #expect(result.searxngStrategy == "fastest")
    }

    @Test func exaModeDefaultsWhenEmpty() {
        var config = Config()
        config.enginesExa.mode = ""
        let result = config.normalized()
        #expect(result.enginesExa.mode == "auto")
    }

    @Test func exaMcpToolDefaultsWhenEmpty() {
        var config = Config()
        config.enginesExa.mcpTool = ""
        let result = config.normalized()
        #expect(result.enginesExa.mcpTool == "exa-web-search")
    }

    @Test func exaNumResultsDefaultsWhenZero() {
        var config = Config()
        config.enginesExa.numResults = 0
        let result = config.normalized()
        #expect(result.enginesExa.numResults == 10)
    }

    @Test func exaNumResultsDefaultsWhenNegative() {
        var config = Config()
        config.enginesExa.numResults = -5
        let result = config.normalized()
        #expect(result.enginesExa.numResults == 10)
    }

    @Test func exaNumResultsPreservedWhenPositive() {
        var config = Config()
        config.enginesExa.numResults = 25
        let result = config.normalized()
        #expect(result.enginesExa.numResults == 25)
    }

    @Test func jinaBaseURLDefaultsWhenEmpty() {
        var config = Config()
        config.enginesJina.baseURL = ""
        let result = config.normalized()
        #expect(result.enginesJina.baseURL == "https://s.jina.ai")
    }

    @Test func jinaBaseURLPreservedWhenNonEmpty() {
        var config = Config()
        config.enginesJina.baseURL = "https://custom.jina.ai"
        let result = config.normalized()
        #expect(result.enginesJina.baseURL == "https://custom.jina.ai")
    }

    @Test func normalizedRebuildsSearxngURLs() {
        var config = Config()
        config.searxngURL  = "https://primary.example.com"
        config.searxngURLs = ["https://secondary.example.com"]
        let result = config.normalized()
        #expect(result.searxngURLs == [
            "https://primary.example.com",
            "https://secondary.example.com",
        ])
    }

    @Test func resultCountDefaultsWhenNonPositive() {
        for bad in [0, -1] {
            var config = Config()
            config.resultCount = bad
            #expect(config.normalized().resultCount == 10)
        }
    }

    @Test func resultCountPreservedWhenPositive() {
        var config = Config()
        config.resultCount = 7
        #expect(config.normalized().resultCount == 7)
    }

    @Test func timeoutDefaultsWhenNonPositive() {
        for bad in [0.0, -2.0] {
            var config = Config()
            config.timeout = bad
            #expect(config.normalized().timeout == 30.0)
        }
    }

    @Test func timeoutPreservedWhenPositive() {
        var config = Config()
        config.timeout = 12.5
        #expect(config.normalized().timeout == 12.5)
    }

    @Test func timeoutDefaultsWhenNonFinite() {
        // nan / ±inf slip past a `<= 0` check, so they must be reset too.
        for bad in [Double.nan, .infinity, -.infinity] {
            var config = Config()
            config.timeout = bad
            #expect(config.normalized().timeout == 30.0)
        }
    }

    @Test func tavilySearchDepthDefaultsWhenEmpty() {
        var config = Config()
        config.enginesTavily.searchDepth = ""
        #expect(config.normalized().enginesTavily.searchDepth == "basic")
    }
}

// MARK: - deduplicateSearxngURLs

@Suite struct DeduplicateSearxngURLsTests {

    @Test func primaryComesFirst() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "https://a.example.com",
            urls: ["https://b.example.com"]
        )
        #expect(result == ["https://a.example.com", "https://b.example.com"])
    }

    @Test func duplicatesRemoved() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "https://a.example.com",
            urls: ["https://b.example.com", "https://a.example.com", "https://b.example.com"]
        )
        #expect(result == ["https://a.example.com", "https://b.example.com"])
    }

    @Test func emptyStringsDropped() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "",
            urls: ["https://a.example.com", "", "https://b.example.com"]
        )
        #expect(result == ["https://a.example.com", "https://b.example.com"])
    }

    @Test func whitespaceOnlyEntriesDropped() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "  ",
            urls: ["https://a.example.com", "  "]
        )
        #expect(result == ["https://a.example.com"])
    }

    @Test func leadingTrailingWhitespaceTrimmed() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "  https://a.example.com  ",
            urls: ["  https://b.example.com  "]
        )
        #expect(result == ["https://a.example.com", "https://b.example.com"])
    }

    @Test func emptyPrimaryAndEmptyURLs() {
        let result = Config.deduplicateSearxngURLs(prepending: "", urls: [])
        #expect(result == [])
    }

    @Test func preservesFirstSeenOrder() {
        let result = Config.deduplicateSearxngURLs(
            prepending: "https://c.example.com",
            urls: ["https://a.example.com", "https://b.example.com", "https://a.example.com"]
        )
        #expect(result == [
            "https://c.example.com",
            "https://a.example.com",
            "https://b.example.com",
        ])
    }
}

// MARK: - configFilePath

@Suite struct ConfigFilePathTests {

    @Test func usesXDGConfigHomeWhenSet() {
        let env = ["XDG_CONFIG_HOME": "/x"]
        let path = Config.configFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/x/sx/config.toml")
    }

    @Test func fallsBackToHomeConfigWhenXDGAbsent() {
        let path = Config.configFilePath(env: [:], homeDirectory: "/home/u")
        #expect(path == "/home/u/.config/sx/config.toml")
    }

    @Test func fallsBackToHomeConfigWhenXDGEmpty() {
        let env = ["XDG_CONFIG_HOME": ""]
        let path = Config.configFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/home/u/.config/sx/config.toml")
    }

    @Test func xdgValueIsUsedVerbatim() {
        let env = ["XDG_CONFIG_HOME": "/custom/xdg/config"]
        let path = Config.configFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/custom/xdg/config/sx/config.toml")
    }

    @Test func ignoresRelativeXDGConfigHome() {
        // A relative XDG_CONFIG_HOME is invalid per the XDG spec → fall back.
        let env = ["XDG_CONFIG_HOME": "relative/config"]
        let path = Config.configFilePath(env: env, homeDirectory: "/home/u")
        #expect(path == "/home/u/.config/sx/config.toml")
    }
}
