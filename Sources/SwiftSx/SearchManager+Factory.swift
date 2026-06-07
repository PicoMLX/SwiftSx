/// Builds a fully-wired ``SearchManager`` (and its backend registry) from a
/// ``Config``. This is the single place that knows the set of supported engines,
/// so both the CLI and any embedder (e.g. SwiftBash) construct the search
/// pipeline the same way.
extension SearchManager {

    /// The names of every engine this build supports, in a stable order.
    ///
    /// Useful for help text, shell completion, and validation. Kept in sync with
    /// the registry assembled by ``make(from:)``.
    public static let knownEngines: [String] = ["searxng", "brave", "tavily", "exa", "jina"]

    /// Build a ``SearchManager`` from `config`.
    ///
    /// Every known engine is instantiated and registered unconditionally — each
    /// backend reports its own `isAvailable`, so an engine that isn't configured
    /// simply fails closed at search time with an actionable hint rather than
    /// being silently absent. The primary engine is `config.engine` and the
    /// fallback chain is `config.fallbackEngines`, both validated against the
    /// registry by ``SearchManager/init(registry:primary:fallbacks:)``.
    ///
    /// No network traffic occurs here: the backends only build their transports.
    ///
    /// - Parameter config: The active configuration.
    /// - Returns: A ready-to-query manager.
    /// - Throws: ``SxError`` with code `.usage` when `config.engine` or any
    ///   entry of `config.fallbackEngines` is not a known engine.
    public static func make(from config: Config) throws -> SearchManager {
        try SearchManager(
            registry: makeRegistry(from: config),
            primary: config.engine,
            fallbacks: config.fallbackEngines
        )
    }

    /// Builds the registry of all known backends from `config`, without choosing a
    /// primary or validating any engine names.
    ///
    /// The command layer uses this for an explicit `--engine` run, where the
    /// config's default/fallback engines must not be validated (and so must not be
    /// able to block a single-engine search).
    public static func makeRegistry(from config: Config) -> [String: any SearchBackend] {
        [
            "searxng": SearxngBackend.makeBackend(from: config),
            "brave":   BraveBackend.makeBrave(from: config),
            "tavily":  TavilyBackend.makeTavily(from: config),
            "exa":     ExaBackend.makeExa(from: config),
            "jina":    JinaBackend.makeJina(from: config),
        ]
    }
}
