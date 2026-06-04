import Foundation

// MARK: - MultiSearxngBackend

/// A multi-instance SearXNG backend that distributes queries across a list of
/// ``SearxngBackend`` instances according to a configured strategy.
///
/// Two strategies are supported:
/// - `"ordered"` (default): try each available instance in order; the first
///   success wins. Falls through to the next instance only on failure.
/// - `"parallel-fastest"`: race all available instances concurrently; return
///   the first successful result and cancel the rest.
///
/// Any unknown strategy string is treated as `"ordered"`.
public struct MultiSearxngBackend: SearchBackend {

    // MARK: - Properties

    /// The configured SearXNG instances, in priority order.
    public let instances: [SearxngBackend]
    /// The dispatch strategy: `"ordered"` or `"parallel-fastest"`.
    public let strategy: String

    // MARK: - Init

    public init(instances: [SearxngBackend], strategy: String = "ordered") {
        self.instances = instances
        self.strategy  = strategy
    }

    // MARK: - SearchBackend

    public var name: String { "searxng" }

    /// `true` when at least one instance is available.
    public var isAvailable: Bool {
        instances.contains { $0.isAvailable }
    }

    /// Execute a search according to the configured strategy.
    ///
    /// - Throws: `BackendError(.network, …)` when all instances fail.
    public func search(_ options: SearchOptions) async throws -> [SearchResult] {
        let available = instances.filter { $0.isAvailable }

        switch strategy {
        case "parallel-fastest":
            return try await parallelFastest(available, options: options)
        default:
            // "ordered" and any unknown strategy.
            return try await ordered(available, options: options)
        }
    }

    // MARK: - Ordered strategy

    private func ordered(
        _ available: [SearxngBackend],
        options: SearchOptions
    ) async throws -> [SearchResult] {
        var errors: [String] = []

        for instance in available {
            do {
                return try await instance.search(options)
            } catch {
                errors.append("\(instance.baseURL): \(errorMessage(from: error))")
            }
        }

        // All failed (or no instances were available).
        let detail = errors.isEmpty ? "no instances configured" : errors.joined(separator: "; ")
        throw BackendError(
            backend: "searxng",
            code: .network,
            message: "all searxng instances failed: \(detail)"
        )
    }

    // MARK: - Parallel-fastest strategy

    private func parallelFastest(
        _ available: [SearxngBackend],
        options: SearchOptions
    ) async throws -> [SearchResult] {
        guard !available.isEmpty else {
            throw BackendError(
                backend: "searxng",
                code: .network,
                message: "all searxng instances failed: no instances configured"
            )
        }

        return try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for instance in available {
                group.addTask {
                    try await instance.search(options)
                }
            }

            // Consume results as they finish. Unlike `for try await` (which would
            // re-throw on the first *failure*), pulling with `group.next()` inside
            // a do/catch lets us ignore individual failures and return the first
            // *success* — true "fastest wins" semantics.
            var errors: [String] = []
            for _ in available {
                do {
                    guard let results = try await group.next() else { break }
                    group.cancelAll()
                    return results
                } catch {
                    errors.append(errorMessage(from: error))
                }
            }

            group.cancelAll()
            let detail = errors.isEmpty ? "no results" : errors.joined(separator: "; ")
            throw BackendError(
                backend: "searxng",
                code: .network,
                message: "all searxng instances failed: \(detail)"
            )
        }
    }

    // MARK: - Private helpers

    private func errorMessage(from error: any Error) -> String {
        if let be = error as? BackendError { return be.message }
        return String(describing: error)
    }
}
