extension Config {
    /// Returns a copy of this config with sensible defaults applied to fields
    /// that were left empty or invalid.
    ///
    /// Rules applied (in order):
    /// 1. `searxngStrategy` → `"ordered"` when empty.
    /// 2. `enginesExa.mode` → `"auto"` when empty.
    /// 3. `enginesExa.mcpTool` → `"exa-web-search"` when empty.
    /// 4. `enginesExa.numResults` → `10` when `<= 0`.
    /// 5. `enginesJina.baseURL` → `"https://s.jina.ai"` when empty.
    /// 6. `searxngURLs` is rebuilt by deduplicating, prepending `searxngURL`.
    public func normalized() -> Config {
        var copy = self

        if copy.searxngStrategy.isEmpty {
            copy.searxngStrategy = "ordered"
        }

        if copy.enginesExa.mode.isEmpty {
            copy.enginesExa.mode = "auto"
        }
        if copy.enginesExa.mcpTool.isEmpty {
            copy.enginesExa.mcpTool = "exa-web-search"
        }
        if copy.enginesExa.numResults <= 0 {
            copy.enginesExa.numResults = 10
        }

        if copy.enginesJina.baseURL.isEmpty {
            copy.enginesJina.baseURL = "https://s.jina.ai"
        }

        copy.searxngURLs = Config.deduplicateSearxngURLs(
            prepending: copy.searxngURL,
            urls: copy.searxngURLs
        )

        return copy
    }

    /// Builds a deduplicated, ordered list of SearXNG instance URLs.
    ///
    /// Algorithm:
    /// 1. Prepend `primary` to `urls` to form the candidate list.
    /// 2. Trim leading/trailing whitespace from each entry.
    /// 3. Drop empty strings.
    /// 4. Remove duplicates, preserving first-seen order.
    ///    (If `primary` is non-empty it stays at index 0.)
    ///
    /// - Parameters:
    ///   - primary: The value of `searxng_url` (may be empty).
    ///   - urls: The values of `searxng_urls` (may be empty).
    /// - Returns: A deduplicated list with `primary` first (when non-empty).
    public static func deduplicateSearxngURLs(
        prepending primary: String,
        urls: [String]
    ) -> [String] {
        let candidates = ([primary] + urls).map { $0.trimmingCharacters(in: .whitespaces) }
        var seen = Set<String>()
        var result = [String]()
        for url in candidates {
            guard !url.isEmpty else { continue }
            if seen.insert(url).inserted {
                result.append(url)
            }
        }
        return result
    }
}
