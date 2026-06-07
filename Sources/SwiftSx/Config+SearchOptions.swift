extension Config {

    /// The baseline ``SearchOptions`` implied by this configuration.
    ///
    /// This maps the config's standing query defaults (categories, SearXNG
    /// engine set, language, safe-search level, and result count) into a
    /// ``SearchOptions``. The per-invocation fields a caller supplies on the
    /// command line — `query`, `site`, `timeRange`, `pageNo`, and any
    /// `numResults` override — are left at their defaults here for the command
    /// layer to overlay.
    ///
    /// - Returns: A ``SearchOptions`` carrying this config's query defaults.
    public func baseSearchOptions() -> SearchOptions {
        SearchOptions(
            query: "",
            categories: categories,
            engines: engines,
            language: language,
            timeRange: "",
            site: "",
            safeSearch: safeSearch,
            pageNo: 1,
            numResults: resultCount
        )
    }
}
