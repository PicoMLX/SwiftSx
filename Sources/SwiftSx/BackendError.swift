/// The class of failure that a search backend encountered.
public enum BackendErrorCode: Sendable, Equatable {
    /// The backend is not configured (missing API key, no instance URL, etc.).
    case unavailable
    /// A network-level failure (DNS, connection refused, timeout, etc.).
    case network
    /// Authentication or authorisation failure (HTTP 401/403).
    case auth
    /// Rate-limit exceeded (HTTP 429).
    case rateLimit
    /// The backend returned a response that could not be parsed.
    case invalidResponse
}

/// A typed failure from a specific search backend.
///
/// The `message` should be actionable and agent-readable — naming the env var,
/// config key, or corrective step — without a `sx:` prefix (the command layer
/// adds that when surfacing it to the user).
public struct BackendError: Error, Sendable, Equatable {
    /// The backend that produced the error (e.g. `"brave"`, `"searxng"`).
    public let backend: String
    /// The class of failure.
    public let code: BackendErrorCode
    /// Actionable description (no `sx:` prefix).
    public let message: String

    public init(backend: String, code: BackendErrorCode, message: String) {
        self.backend = backend
        self.code    = code
        self.message = message
    }
}

// MARK: - BackendErrorCode → SxExitCode mapping

public extension BackendErrorCode {
    /// The ``SxExitCode`` that best represents this error class.
    ///
    /// Fail-closed codes (`.unavailable`, `.auth`, `.network`) map to `.auth`
    /// (7) because they signal a configuration or infrastructure problem that
    /// the agent cannot resolve by retrying with the same command.
    ///
    /// Transient / recoverable codes (`.rateLimit`, `.invalidResponse`) map to
    /// `.general` (1).
    var sxExitCode: SxExitCode {
        switch self {
        case .unavailable:       return .auth
        case .auth:              return .auth
        case .network:           return .auth
        case .rateLimit:         return .general
        case .invalidResponse:   return .general
        }
    }
}
