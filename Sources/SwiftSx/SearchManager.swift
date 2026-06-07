/// The outcome of a successful search: the results and the engine that
/// produced them.
public struct SearchOutcome: Sendable, Equatable {
    /// The search results returned by the winning backend.
    public let results: [SearchResult]
    /// The name of the backend that produced these results.
    public let engine: String

    public init(results: [SearchResult], engine: String) {
        self.results = results
        self.engine  = engine
    }
}

// MARK: -

/// Routes search queries to the primary backend with automatic fallback.
///
/// On construction, `SearchManager` validates that every named engine exists
/// in the registry. At query time it tries the primary backend first; on any
/// failure it works through the fallback chain in order, skipping backends
/// that are not available. If every attempt fails it throws an aggregate
/// ``SxError`` whose message lists each backend and its failure reason.
///
/// This mirrors the behaviour of the upstream Go `manager.go`.
public struct SearchManager: Sendable {

    // MARK: - State

    private let registry: [String: any SearchBackend]
    private let primary: any SearchBackend
    private let fallbacks: [any SearchBackend]

    // MARK: - Init

    /// Create a manager from a pre-built registry.
    ///
    /// - Parameters:
    ///   - registry: A dictionary of all known backends, keyed by their `name`.
    ///   - primary: The name of the backend to try first.
    ///   - fallbacks: Names of backends to try, in order, when the primary fails.
    /// - Throws: ``SxError`` with code `.usage` if `primary` or any fallback
    ///   name is absent from `registry`.
    public init(
        registry: [String: any SearchBackend],
        primary: String,
        fallbacks: [String]
    ) throws {
        self.registry = registry

        guard let primaryBackend = registry[primary] else {
            let valid = registry.keys.sorted().joined(separator: ", ")
            throw SxError(.usage, "unknown engine '\(primary)'; valid engines: \(valid)")
        }
        self.primary = primaryBackend

        var resolvedFallbacks: [any SearchBackend] = []
        for name in fallbacks {
            guard let backend = registry[name] else {
                let valid = registry.keys.sorted().joined(separator: ", ")
                throw SxError(.usage, "unknown engine '\(name)'; valid engines: \(valid)")
            }
            resolvedFallbacks.append(backend)
        }
        self.fallbacks = resolvedFallbacks
    }

    // MARK: - Search (primary → fallback chain)

    /// Search using the primary backend, falling back through the configured
    /// chain on any failure.
    ///
    /// - Parameter options: The query parameters.
    /// - Returns: A ``SearchOutcome`` naming the backend that responded.
    /// - Throws: An aggregate ``SxError`` if every backend in the chain fails.
    public func search(_ options: SearchOptions) async throws -> SearchOutcome {
        /// A failure record: the display string and whether it was fail-closed.
        struct FailureRecord {
            let label: String
            let isFailClosed: Bool
        }

        var failures: [FailureRecord] = []

        // Try primary — but skip the request entirely if it isn't configured,
        // consistent with how fallbacks are handled.
        if primary.isAvailable {
            do {
                let results = try await primary.search(options)
                return SearchOutcome(results: results, engine: primary.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch let sxError as SxError {
                throw sxError   // e.g. a sandbox refusal — propagate, don't fall back
            } catch {
                failures.append(FailureRecord(
                    label: "\(primary.name): \(reasonString(from: error))",
                    isFailClosed: isFailClosed(error)
                ))
            }
        } else {
            failures.append(FailureRecord(
                label: "\(primary.name): not configured — \(Self.configurationHint(for: primary.name))",
                isFailClosed: true
            ))
        }

        // Try each fallback in order.
        for fallback in fallbacks {
            guard fallback.isAvailable else {
                // "not configured" counts as fail-closed (same as .unavailable).
                failures.append(FailureRecord(
                    label: "\(fallback.name): not configured — \(Self.configurationHint(for: fallback.name))",
                    isFailClosed: true
                ))
                continue
            }
            do {
                let results = try await fallback.search(options)
                return SearchOutcome(results: results, engine: fallback.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch let sxError as SxError {
                throw sxError
            } catch {
                failures.append(FailureRecord(
                    label: "\(fallback.name): \(reasonString(from: error))",
                    isFailClosed: isFailClosed(error)
                ))
            }
        }

        // All backends failed — build an aggregate error.
        let message = "all search backends failed:\n"
            + failures.map { "  - \($0.label)" }.joined(separator: "\n")

        // Exit code is .auth only when every failure was fail-closed.
        let exitCode: SxExitCode = failures.allSatisfy(\.isFailClosed) ? .auth : .general
        throw SxError(exitCode, message)
    }

    // MARK: - Explicit engine (no fallback)

    /// Search using a specific backend by name, with no fallback.
    ///
    /// - Parameters:
    ///   - engine: The name of the backend to use.
    ///   - options: The query parameters.
    /// - Returns: A ``SearchOutcome`` for the named engine.
    /// - Throws:
    ///   - ``SxError`` with code `.usage` if the engine is not in the registry.
    ///   - ``SxError`` with code `.auth` if the engine is in the registry but
    ///     `isAvailable` is `false`.
    ///   - ``SxError`` (mapped via ``BackendErrorCode/sxExitCode``) when the
    ///     backend itself fails, so the explicit path carries the same stable
    ///     exit-code contract as the fallback path.
    public func searchExplicit(
        _ engine: String,
        _ options: SearchOptions
    ) async throws -> SearchOutcome {
        guard let backend = registry[engine] else {
            let valid = registry.keys.sorted().joined(separator: ", ")
            throw SxError(.usage, "unknown engine '\(engine)'; valid engines: \(valid)")
        }
        guard backend.isAvailable else {
            throw SxError(
                .auth,
                "engine '\(engine)' is not configured — \(Self.configurationHint(for: engine))"
            )
        }
        do {
            let results = try await backend.search(options)
            return SearchOutcome(results: results, engine: backend.name)
        } catch is CancellationError {
            throw CancellationError()
        } catch let sxError as SxError {
            throw sxError   // e.g. a sandbox refusal — propagate as-is
        } catch let error as BackendError {
            // Convert to the stable exit-code contract, mirroring the fallback path.
            throw SxError(error.code.sxExitCode, error.message)
        } catch {
            // Any other error — e.g. a raw URLSession or decoder error that
            // escaped a backend's wrapping — must not bypass the contract. Map
            // it to a stable exit code instead of leaking a raw description,
            // mirroring how the fallback path treats a non-BackendError (not
            // fail-closed → exit 1).
            throw SxError(.general, "engine '\(engine)' failed: \(error)")
        }
    }

    // MARK: - Private helpers

    /// A concrete, actionable hint naming the config key / env var to set for an
    /// unconfigured engine, so fail-closed messages point to a real fix.
    static func configurationHint(for engine: String) -> String {
        switch engine {
        case "searxng": return "set searxng_url (and optionally searxng_urls) in config.toml"
        case "brave":   return "set BRAVE_API_KEY or engines_brave.api_key"
        case "tavily":  return "set TAVILY_API_KEY or engines_tavily.api_key"
        case "exa":     return "set EXA_API_KEY / engines_exa.api_key, or engines_exa.mcp_url"
        case "jina":    return "set JINA_API_KEY or engines_jina.api_key (or engines_jina.allow_keyless)"
        default:        return "configure this engine in config.toml"
        }
    }

    /// Extract a short reason string from a thrown error.
    private func reasonString(from error: any Error) -> String {
        if let be = error as? BackendError {
            return be.message
        }
        return String(describing: error)
    }

    /// Returns `true` when the error represents a fail-closed condition
    /// (`.unavailable`, `.auth`, or `.network`) that maps to exit code `.auth`.
    private func isFailClosed(_ error: any Error) -> Bool {
        guard let be = error as? BackendError else { return false }
        switch be.code {
        case .unavailable, .auth, .network: return true
        case .rateLimit, .invalidResponse:  return false
        }
    }
}
