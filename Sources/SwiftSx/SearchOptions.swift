/// Query parameters passed to a search backend.
///
/// All fields default to sensible values so a caller can set only what they
/// need. `SearchOptions()` is a valid minimal query (though `query` should
/// be set before use).
public struct SearchOptions: Sendable, Equatable {

    // MARK: - Fields

    /// The search query string.
    public var query: String

    /// Result categories to include (e.g. `["general", "news"]`).
    /// Empty means "use the backend's default".
    public var categories: [String]

    /// SearXNG-internal engine names to include in the query.
    /// Empty means "use the backend's default set".
    public var engines: [String]

    /// Language / locale code (e.g. `"en-US"`). Empty means server default.
    public var language: String

    /// Time range filter (e.g. `"day"`, `"week"`, `"month"`, `"year"`).
    /// Empty means no filter.
    public var timeRange: String

    /// Restrict results to a specific site (e.g. `"github.com"`).
    /// Empty means no restriction.
    public var site: String

    /// Safe-search level: `"strict"` (default), `"moderate"`, or `"off"`.
    public var safeSearch: String

    /// Pagination: 1-indexed page number. Default: `1`.
    public var pageNo: Int

    /// Maximum number of results to return. Default: `10`.
    public var numResults: Int

    // MARK: - Memberwise init (all defaults)

    public init(
        query: String = "",
        categories: [String] = [],
        engines: [String] = [],
        language: String = "",
        timeRange: String = "",
        site: String = "",
        safeSearch: String = "strict",
        pageNo: Int = 1,
        numResults: Int = 10
    ) {
        self.query      = query
        self.categories = categories
        self.engines    = engines
        self.language   = language
        self.timeRange  = timeRange
        self.site       = site
        self.safeSearch = safeSearch
        self.pageNo     = pageNo
        self.numResults = numResults
    }
}
