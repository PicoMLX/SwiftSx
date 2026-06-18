import Foundation

extension Config {
    /// Returns a copy of this config with sensible defaults applied to fields
    /// that were left empty or invalid.
    ///
    /// Rules applied (in order):
    /// 1. `searxngStrategy` → `"ordered"` when empty.
    /// 2. `resultCount` → `10` when `<= 0`.
    /// 3. `timeout` → `30.0` when `<= 0`.
    /// 4. `enginesExa.mode` → `"auto"` when empty.
    /// 5. `enginesExa.mcpTool` → `"exa-web-search"` when empty.
    /// 6. `enginesExa.numResults` → `10` when `<= 0`.
    /// 7. `enginesTavily.searchDepth` → `"basic"` when empty.
    /// 8. `enginesJina.baseURL` → `"https://s.jina.ai"` when empty.
    /// 9. `searxngURLs` is rebuilt by deduplicating, prepending `searxngURL`.
    public func normalized() -> Config {
        var copy = self

        if copy.searxngStrategy.isEmpty {
            copy.searxngStrategy = "ordered"
        }

        // Clamp query knobs that would otherwise make queries fail or hang.
        if copy.resultCount <= 0 {
            copy.resultCount = 10
        }
        if copy.timeout <= 0 || !copy.timeout.isFinite {
            // Also reset non-finite values (nan / ±inf), which would otherwise
            // slip past a `<= 0` check and make every request hang or fail.
            copy.timeout = 30.0
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

        if copy.enginesTavily.searchDepth.isEmpty {
            copy.enginesTavily.searchDepth = "basic"
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
