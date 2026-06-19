import Testing

// MARK: - AsyncMutex

/// A minimal FIFO async mutual-exclusion lock that can be *held across
/// suspension points*.
///
/// An `NSLock` (as used by `TestLockedBox`) cannot be held across an `await`,
/// but a test scope needs exactly that: the work passed to
/// ``MockURLProtocolSerializedTrait/provideScope(for:testCase:performing:)`` is
/// `async`. Built on an `actor`, so its own state transitions are race-free;
/// `unlock()` hands ownership directly to the next waiter, so no wakeup is lost.
///
/// Note: waiting is not cancellation-aware. That is acceptable here because test
/// suites are not cancelled while queued for this lock.
actor AsyncMutex {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Acquire the lock, suspending (in FIFO order) until it is free.
    func lock() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Release the lock, handing it to the next queued waiter if there is one.
    func unlock() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            // Transfer ownership directly: `isHeld` stays true, so no other task
            // can acquire between this call and the resumed waiter proceeding.
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Cross-suite serialization of MockURLProtocol.handler

/// Process-global gate shared by every suite that mutates
/// ``MockURLProtocol/handler``.
private let mockURLProtocolGate = AsyncMutex()

/// A suite trait that serializes a suite against *every other* suite carrying
/// it, by holding one process-global lock for the suite's entire run.
///
/// Swift Testing's built-in `.serialized` only orders tests **within** a single
/// suite; distinct suites still run concurrently. Because
/// ``MockURLProtocol/handler`` is process-global, two handler-mutating suites
/// running at once can clobber each other's handler — a latent parallel-test
/// flake. (CI runs `swift test --no-parallel`, so today it would only bite a
/// local parallel run.) Annotating those suites with `.mockURLProtocolSerialized`
/// routes them all through ``mockURLProtocolGate``, so at most one runs at a time.
///
/// Scope is provided only at suite level (`testCase == nil`), which
/// `TestScoping.provideScope(for:testCase:performing:)` documents as wrapping the
/// suite's entire run; the lock is taken once per suite, not once per test. Pair
/// it with `.serialized`, which still orders the suite's own tests.
struct MockURLProtocolSerializedTrait: SuiteTrait, TestScoping {
    // The default `scopeProvider` (from `Trait where Self: TestScoping`) scopes
    // per test case; override to scope at suite level instead so the lock wraps
    // the whole suite and is never re-entered.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? self : nil
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await mockURLProtocolGate.lock()
        do {
            try await function()
        } catch {
            await mockURLProtocolGate.unlock()
            throw error
        }
        await mockURLProtocolGate.unlock()
    }
}

extension Trait where Self == MockURLProtocolSerializedTrait {
    /// Serialize this suite against all other suites that mutate the shared
    /// `MockURLProtocol.handler`. Apply *alongside* `.serialized`.
    static var mockURLProtocolSerialized: Self { MockURLProtocolSerializedTrait() }
}
