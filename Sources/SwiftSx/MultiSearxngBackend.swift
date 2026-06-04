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
    /// - Throws: an aggregate `BackendError` when all instances fail (preserving
    ///   a shared error code when every instance failed the same way);
    ///   `CancellationError` / `SxError` propagate immediately.
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

    /// A single instance failure: its message and classified code (if any).
    private struct Failure {
        let message: String
        let code: BackendErrorCode?
    }

    // MARK: - Ordered strategy

    private func ordered(
        _ available: [SearxngBackend],
        options: SearchOptions
    ) async throws -> [SearchResult] {
        var failures: [Failure] = []

        for instance in available {
            try Task.checkCancellation()
            do {
                return try await instance.search(options)
            } catch is CancellationError {
                throw CancellationError()
            } catch let sx as SxError {
                throw sx          // sandbox refusal — propagate, don't try the rest
            } catch {
                failures.append(Failure(
                    message: "\(instance.baseURL): \(errorMessage(from: error))",
                    code: (error as? BackendError)?.code
                ))
            }
        }

        throw aggregate(failures)
    }

    // MARK: - Parallel-fastest strategy

    private func parallelFastest(
        _ available: [SearxngBackend],
        options: SearchOptions
    ) async throws -> [SearchResult] {
        guard !available.isEmpty else { throw aggregate([]) }

        return try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for instance in available {
                group.addTask {
                    try await instance.search(options)
                }
            }

            // Pull with `group.next()` (not `for try await`, which re-throws on the
            // first *failure*) so we return the first *success* and tolerate
            // per-instance failures. Cancellation / sandbox refusals propagate.
            var failures: [Failure] = []
            for _ in available {
                do {
                    guard let results = try await group.next() else { break }
                    group.cancelAll()
                    return results
                } catch is CancellationError {
                    group.cancelAll()
                    throw CancellationError()
                } catch let sx as SxError {
                    group.cancelAll()
                    throw sx
                } catch {
                    failures.append(Failure(
                        message: errorMessage(from: error),
                        code: (error as? BackendError)?.code
                    ))
                }
            }

            group.cancelAll()
            throw aggregate(failures)
        }
    }

    // MARK: - Private helpers

    /// Build the aggregate failure error. When every instance failed with the
    /// same classified code (e.g. all `.rateLimit`), that code is preserved so
    /// the agent still gets the actionable path; otherwise `.network`.
    private func aggregate(_ failures: [Failure]) -> BackendError {
        let detail = failures.isEmpty
            ? "no instances configured"
            : failures.map(\.message).joined(separator: "; ")

        let codes = failures.compactMap(\.code)
        let code: BackendErrorCode
        if !failures.isEmpty, codes.count == failures.count,
           let first = codes.first, codes.allSatisfy({ $0 == first }) {
            code = first
        } else {
            code = .network
        }

        return BackendError(
            backend: "searxng",
            code: code,
            message: "all searxng instances failed: \(detail)"
        )
    }

    private func errorMessage(from error: any Error) -> String {
        if let be = error as? BackendError { return be.message }
        return String(describing: error)
    }
}
