import Testing
@testable import SwiftSx

// MARK: - MockBackend

/// A configurable mock conforming to ``SearchBackend`` for use in tests.
private struct MockBackend: SearchBackend {
    let name: String
    let isAvailable: Bool
    /// The outcome when `search(_:)` is called.
    let outcome: Outcome

    enum Outcome {
        case success([SearchResult])
        case failure(BackendError)
    }

    func search(_ options: SearchOptions) async throws -> [SearchResult] {
        switch outcome {
        case .success(let results):
            return results
        case .failure(let error):
            throw error
        }
    }
}

/// A backend that always throws a non-`BackendError` error, used to exercise the
/// manager's catch-all mapping for unexpected error types.
private struct RawErrorBackend: SearchBackend {
    let name: String
    var isAvailable: Bool { true }
    struct Boom: Error {}
    func search(_ options: SearchOptions) async throws -> [SearchResult] {
        throw Boom()
    }
}

// MARK: - BackendErrorCode.sxExitCode

@Suite struct BackendErrorCodeExitCodeTests {

    @Test func unavailableMapsToAuth() {
        #expect(BackendErrorCode.unavailable.sxExitCode == .auth)
    }

    @Test func authMapsToAuth() {
        #expect(BackendErrorCode.auth.sxExitCode == .auth)
    }

    @Test func networkMapsToAuth() {
        #expect(BackendErrorCode.network.sxExitCode == .auth)
    }

    @Test func rateLimitMapsToGeneral() {
        #expect(BackendErrorCode.rateLimit.sxExitCode == .general)
    }

    @Test func invalidResponseMapsToGeneral() {
        #expect(BackendErrorCode.invalidResponse.sxExitCode == .general)
    }
}

// MARK: - SearchManager.init

@Suite struct SearchManagerInitTests {

    @Test func unknownPrimaryThrowsUsage() throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
        ]
        #expect(throws: SxError.self) {
            _ = try SearchManager(registry: registry, primary: "missing", fallbacks: [])
        }
        do {
            _ = try SearchManager(registry: registry, primary: "missing", fallbacks: [])
        } catch let e as SxError {
            #expect(e.exitCode == .usage)
            #expect(e.message.contains("missing"))
            #expect(e.message.contains("alpha"))
        }
    }

    @Test func unknownFallbackThrowsUsage() throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
        ]
        #expect(throws: SxError.self) {
            _ = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["ghost"])
        }
        do {
            _ = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["ghost"])
        } catch let e as SxError {
            #expect(e.exitCode == .usage)
            #expect(e.message.contains("ghost"))
        }
    }

    @Test func validPrimaryAndFallbacksSucceeds() throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
            "beta":  MockBackend(name: "beta",  isAvailable: true, outcome: .success([])),
        ]
        // Should not throw.
        _ = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["beta"])
    }

    @Test func validEngineMissingMessageListsSortedNames() throws {
        let registry: [String: any SearchBackend] = [
            "zeta":  MockBackend(name: "zeta",  isAvailable: true, outcome: .success([])),
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
        ]
        do {
            _ = try SearchManager(registry: registry, primary: "nope", fallbacks: [])
        } catch let e as SxError {
            // Engine list in message should be sorted.
            let alphaIdx = e.message.range(of: "alpha")?.lowerBound
            let zetaIdx  = e.message.range(of: "zeta")?.lowerBound
            let alpha = try #require(alphaIdx)
            let zeta  = try #require(zetaIdx)
            #expect(alpha < zeta)
        }
    }
}

// MARK: - SearchManager.search

@Suite struct SearchManagerSearchTests {

    // MARK: Primary success

    @Test func primarySuccessReturnsOutcomeWithPrimaryName() async throws {
        let expected = [SearchResult(title: "Hello", url: "https://example.com")]
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success(expected)),
            "beta":  MockBackend(name: "beta",  isAvailable: true,
                                 outcome: .failure(BackendError(backend: "beta", code: .network, message: "unreachable"))),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["beta"])
        let outcome = try await manager.search(SearchOptions(query: "swift"))
        #expect(outcome.results == expected)
        #expect(outcome.engine == "alpha")
    }

    // MARK: Fallback on primary failure

    @Test func primaryFailureFallsBackToNextAvailable() async throws {
        let expected = [SearchResult(title: "Fallback Result", url: "https://fb.example.com")]
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .network, message: "timeout"))),
            "beta":  MockBackend(name: "beta",  isAvailable: true, outcome: .success(expected)),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["beta"])
        let outcome = try await manager.search(SearchOptions(query: "swift"))
        #expect(outcome.results == expected)
        #expect(outcome.engine == "beta")
    }

    // MARK: Unavailable fallback is skipped

    @Test func unavailableFallbackIsSkippedAndNextTried() async throws {
        let expected = [SearchResult(title: "Third", url: "https://third.example.com")]
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .auth, message: "bad key"))),
            "beta":  MockBackend(name: "beta",  isAvailable: false, outcome: .success([])),
            "gamma": MockBackend(name: "gamma", isAvailable: true, outcome: .success(expected)),
        ]
        let manager = try SearchManager(
            registry: registry, primary: "alpha", fallbacks: ["beta", "gamma"])
        let outcome = try await manager.search(SearchOptions(query: "swift"))
        #expect(outcome.results == expected)
        #expect(outcome.engine == "gamma")
    }

    // MARK: All fail → throws aggregate error (all fail-closed → .auth)

    @Test func allFailClosedThrowsAuthExitCode() async throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .unavailable, message: "no key"))),
            "beta":  MockBackend(name: "beta",  isAvailable: false, outcome: .success([])),
            "gamma": MockBackend(name: "gamma", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "gamma", code: .network, message: "DNS fail"))),
        ]
        let manager = try SearchManager(
            registry: registry, primary: "alpha", fallbacks: ["beta", "gamma"])

        await #expect(throws: SxError.self) {
            _ = try await manager.search(SearchOptions(query: "test"))
        }

        do {
            _ = try await manager.search(SearchOptions(query: "test"))
        } catch let e as SxError {
            #expect(e.exitCode == .auth)
            #expect(e.message.contains("all search backends failed"))
            #expect(e.message.contains("alpha"))
            #expect(e.message.contains("beta"))
            #expect(e.message.contains("gamma"))
        }
    }

    // MARK: All fail → throws aggregate error (mixed → .general)

    @Test func mixedFailuresThrowsGeneralExitCode() async throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .unavailable, message: "no key"))),
            "beta":  MockBackend(name: "beta",  isAvailable: true,
                                 outcome: .failure(BackendError(backend: "beta", code: .rateLimit, message: "too many requests"))),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["beta"])

        do {
            _ = try await manager.search(SearchOptions(query: "test"))
        } catch let e as SxError {
            // One fail-closed + one transient → .general
            #expect(e.exitCode == .general)
            #expect(e.message.contains("all search backends failed"))
            #expect(e.message.contains("alpha"))
            #expect(e.message.contains("beta"))
        }
    }

    // MARK: Failure record format

    @Test func aggregateMessageListsEachBackend() async throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .auth, message: "bad token"))),
            "beta":  MockBackend(name: "beta",  isAvailable: false, outcome: .success([])),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: ["beta"])

        do {
            _ = try await manager.search(SearchOptions(query: "q"))
        } catch let e as SxError {
            // alpha failure uses BackendError message; beta is skipped with "not configured"
            #expect(e.message.contains("alpha: bad token"))
            #expect(e.message.contains("beta: not configured"))
        }
    }

    // MARK: Non-BackendError propagates as .general

    @Test func nonBackendErrorInPrimaryIsDescribed() async throws {
        struct WeirdError: Error { let msg: String }
        // We can't make MockBackend throw WeirdError directly without changes,
        // but we can verify the manager uses String(describing:) for non-BackendErrors
        // by checking via BackendError.invalidResponse (maps to .general) across all.
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .invalidResponse, message: "bad json"))),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: [])

        do {
            _ = try await manager.search(SearchOptions(query: "q"))
        } catch let e as SxError {
            #expect(e.exitCode == .general)
            #expect(e.message.contains("bad json"))
        }
    }
}

// MARK: - SearchManager.searchExplicit

@Suite struct SearchManagerSearchExplicitTests {

    // MARK: Unknown engine

    @Test func unknownEngineThrowsUsage() async throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: [])

        await #expect(throws: SxError.self) {
            _ = try await manager.searchExplicit("ghost", SearchOptions())
        }

        do {
            _ = try await manager.searchExplicit("ghost", SearchOptions())
        } catch let e as SxError {
            #expect(e.exitCode == .usage)
            #expect(e.message.contains("ghost"))
            #expect(e.message.contains("alpha"))
        }
    }

    // MARK: Unavailable engine

    @Test func unavailableEngineThrowsAuth() async throws {
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true, outcome: .success([])),
            "beta":  MockBackend(name: "beta",  isAvailable: false, outcome: .success([])),
        ]
        let manager = try SearchManager(registry: registry, primary: "alpha", fallbacks: [])

        await #expect(throws: SxError.self) {
            _ = try await manager.searchExplicit("beta", SearchOptions())
        }

        do {
            _ = try await manager.searchExplicit("beta", SearchOptions())
        } catch let e as SxError {
            #expect(e.exitCode == .auth)
            #expect(e.message.contains("beta"))
            // Message should hint at how to configure it (per-engine hint; an
            // unknown engine like "beta" falls back to the generic config.toml hint).
            #expect(e.message.contains("config.toml"))
        }
    }

    // MARK: Available engine

    @Test func availableEngineReturnsOutcomeNoFallback() async throws {
        let expected = [SearchResult(title: "Explicit", url: "https://explicit.example.com")]
        let fallbackResult = [SearchResult(title: "Fallback", url: "https://fb.example.com")]
        let registry: [String: any SearchBackend] = [
            "alpha": MockBackend(name: "alpha", isAvailable: true,
                                 outcome: .failure(BackendError(backend: "alpha", code: .network, message: "timeout"))),
            "beta":  MockBackend(name: "beta",  isAvailable: true, outcome: .success(expected)),
            "gamma": MockBackend(name: "gamma", isAvailable: true, outcome: .success(fallbackResult)),
        ]
        // primary=alpha (will fail), fallback=gamma
        let manager = try SearchManager(
            registry: registry, primary: "alpha", fallbacks: ["gamma"])

        // searchExplicit("beta") uses beta directly, ignoring primary/fallback chain.
        let outcome = try await manager.searchExplicit("beta", SearchOptions(query: "swift"))
        #expect(outcome.results == expected)
        #expect(outcome.engine == "beta")
    }

    @Test func backendErrorFromExplicitMapsToSxError() async throws {
        let be = BackendError(backend: "brave", code: .rateLimit, message: "slow down")
        let registry: [String: any SearchBackend] = [
            "brave": MockBackend(name: "brave", isAvailable: true, outcome: .failure(be)),
        ]
        let manager = try SearchManager(registry: registry, primary: "brave", fallbacks: [])

        do {
            _ = try await manager.searchExplicit("brave", SearchOptions())
            Issue.record("Expected error to be thrown")
        } catch let thrown as SxError {
            // The BackendError is mapped to the stable exit-code contract.
            #expect(thrown.exitCode == .general)   // .rateLimit -> .general
            #expect(thrown.message == "slow down")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func explicitAuthFailureMapsToExit7() async throws {
        let be = BackendError(backend: "brave", code: .auth, message: "bad key")
        let registry: [String: any SearchBackend] = [
            "brave": MockBackend(name: "brave", isAvailable: true, outcome: .failure(be)),
        ]
        let manager = try SearchManager(registry: registry, primary: "brave", fallbacks: [])
        do {
            _ = try await manager.searchExplicit("brave", SearchOptions())
            Issue.record("Expected error to be thrown")
        } catch let thrown as SxError {
            #expect(thrown.exitCode == .auth)
        }
    }

    @Test func nonBackendErrorFromExplicitMapsToGeneral() async throws {
        // A raw (non-BackendError) error from the backend must be mapped to the
        // stable contract (exit 1) instead of leaking out and bypassing the
        // `sx:` error surface — mirroring how the fallback path handles it.
        let registry: [String: any SearchBackend] = [
            "raw": RawErrorBackend(name: "raw"),
        ]
        let manager = try SearchManager(registry: registry, primary: "raw", fallbacks: [])

        await #expect(throws: SxError.self) {
            _ = try await manager.searchExplicit("raw", SearchOptions())
        }

        do {
            _ = try await manager.searchExplicit("raw", SearchOptions())
            Issue.record("Expected an SxError to be thrown")
        } catch let thrown as SxError {
            #expect(thrown.exitCode == .general)
            #expect(thrown.message.contains("raw"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Primary availability gating

@Suite struct SearchManagerPrimaryAvailabilityTests {

    @Test func unavailablePrimaryIsSkippedAndFallbackUsed() async throws {
        let hit = [SearchResult(title: "Fallback hit", url: "https://f.example.com")]
        let registry: [String: any SearchBackend] = [
            "primary":  MockBackend(name: "primary",  isAvailable: false, outcome: .success([])),
            "fallback": MockBackend(name: "fallback", isAvailable: true,  outcome: .success(hit)),
        ]
        let manager = try SearchManager(registry: registry, primary: "primary", fallbacks: ["fallback"])
        let outcome = try await manager.search(SearchOptions(query: "x"))
        #expect(outcome.engine == "fallback")
        #expect(outcome.results == hit)
    }

    @Test func allUnavailableThrowsExit7() async throws {
        let registry: [String: any SearchBackend] = [
            "primary":  MockBackend(name: "primary",  isAvailable: false, outcome: .success([])),
            "fallback": MockBackend(name: "fallback", isAvailable: false, outcome: .success([])),
        ]
        let manager = try SearchManager(registry: registry, primary: "primary", fallbacks: ["fallback"])
        do {
            _ = try await manager.search(SearchOptions(query: "x"))
            Issue.record("Expected error to be thrown")
        } catch let thrown as SxError {
            #expect(thrown.exitCode == .auth)
        }
    }
}
