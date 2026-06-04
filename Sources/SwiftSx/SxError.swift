/// Stable process exit codes for the `sx` tool.
///
/// This CLI is driven by LLM agents, which branch on exit codes. The scheme is
/// deliberately small and **stable** — treat it like an API. See `AGENTS.md`.
public enum SxExitCode: Int32, Sendable, CaseIterable {
    /// Success.
    case success = 0
    /// General / unclassified runtime error (the fallback).
    case general = 1
    /// Usage / bad input — the agent can fix the command and retry.
    case usage = 2
    /// Refused by policy or the sandbox gate — not a retry.
    case refused = 3
    /// No results found, and `--fail-empty` was set.
    case empty = 4
    /// Fail-closed: missing/invalid auth or no network — escalate, don't retry.
    case auth = 7
}

/// An error carrying a stable ``SxExitCode`` and an actionable, agent-readable
/// message.
///
/// Per `llm-friendly-cli-messages`, the `message` should name a concrete next
/// action (the flag, env var, config key, or scope to fix), not just the
/// symptom. Messages are surfaced on stderr, prefixed with `sx:`.
public struct SxError: Error, Sendable, CustomStringConvertible {
    /// The exit code the process should terminate with.
    public let exitCode: SxExitCode
    /// The actionable, human/agent-readable message (without the `sx:` prefix).
    public let message: String

    public init(_ exitCode: SxExitCode, _ message: String) {
        self.exitCode = exitCode
        self.message = message
    }

    public var description: String { message }
}
