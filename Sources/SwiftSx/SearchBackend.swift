/// A search backend that can execute queries and return results.
///
/// Conforming types are expected to be concurrency-safe (`Sendable`). The SDK
/// ships no concrete backend implementations yet — those arrive in later PRs
/// once the HTTP client is wired up.
public protocol SearchBackend: Sendable {
    /// The stable, lowercase name used to identify this backend
    /// (e.g. `"brave"`, `"searxng"`).
    var name: String { get }

    /// Whether this backend is currently configured and ready to be used.
    ///
    /// A backend that is missing its API key or instance URL should return
    /// `false` so the ``SearchManager`` can skip it without issuing a network
    /// request.
    var isAvailable: Bool { get }

    /// Perform a search and return the results.
    ///
    /// - Parameter options: The query parameters for this search.
    /// - Returns: An array of ``SearchResult`` values. May be empty.
    /// - Throws: ``BackendError`` on any backend-specific failure.
    func search(_ options: SearchOptions) async throws -> [SearchResult]
}
