extension Config {
    /// Returns a copy of this config with API keys overridden by the given
    /// environment dictionary.
    ///
    /// Only variables that are **present and non-empty** in `env` override the
    /// corresponding config-file value. Absent or empty env vars leave the
    /// existing value unchanged, so the file always acts as the fallback.
    ///
    /// Mappings:
    /// - `BRAVE_API_KEY`  → `enginesBrave.apiKey`
    /// - `TAVILY_API_KEY` → `enginesTavily.apiKey`
    /// - `EXA_API_KEY`    → `enginesExa.apiKey`
    /// - `JINA_API_KEY`   → `enginesJina.apiKey`
    ///
    /// - Parameter env: A snapshot of the process environment (or a test double).
    public func applyingEnvironmentOverrides(_ env: [String: String]) -> Config {
        var copy = self

        if let value = env["BRAVE_API_KEY"], !value.isEmpty {
            copy.enginesBrave.apiKey = value
        }
        if let value = env["TAVILY_API_KEY"], !value.isEmpty {
            copy.enginesTavily.apiKey = value
        }
        if let value = env["EXA_API_KEY"], !value.isEmpty {
            copy.enginesExa.apiKey = value
        }
        if let value = env["JINA_API_KEY"], !value.isEmpty {
            copy.enginesJina.apiKey = value
        }

        return copy
    }
}
