import ArgumentParser
import Foundation
import ShellKit
import SwiftSx

/// The `sx history` subcommand — list recent search history.
///
/// Prints the most recent entries (oldest-first) to stdout, one per line,
/// formatted as `"  yyyy-MM-dd HH:mm  <query>"`. When no entries exist, a
/// status message is written to stderr. Any ``SxError`` is written to stderr
/// and re-thrown as the appropriate exit code.
public struct HistoryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List or clear recent search history.",
        subcommands: [HistoryClear.self]
    )

    // MARK: Options

    /// Maximum number of history entries to display (most recent).
    @Option(name: [.customShort("n"), .long],
            help: "Number of entries to show (0 = all).")
    public var limit: Int = 20

    public init() {}

    // MARK: Limit resolution

    /// Validates `--limit` and returns the effective count.
    ///
    /// A negative limit is a usage error mapped to exit code `2` (rather than
    /// being silently treated as "show all" by `History.read`). It is handled
    /// here — and surfaced through `run()`'s `SxError` path with an
    /// `sx:`-prefixed diagnostic — instead of via ArgumentParser's `validate()`,
    /// whose default failure path prints its own usage text and bypasses the
    /// tool's documented exit-code contract. Factored out so it is unit-testable
    /// without exercising the I/O path.
    func resolvedLimit() throws -> Int {
        guard limit >= 0 else {
            throw SxError(.usage, "--limit must be 0 or greater (got \(limit)) — pass a non-negative count, or 0 to show all entries")
        }
        return limit
    }

    // MARK: run

    public func run() async throws {
        let stderr = Shell.current.stderr
        let stdout = Shell.current.stdout

        do {
            let effectiveLimit = try resolvedLimit()
            let entries = try await History.read(limit: effectiveLimit)
            if entries.isEmpty {
                stderr.write(Data("sx: no search history yet — run a search to create it\n".utf8))
            } else {
                for entry in entries {
                    stdout.write(Data((History.displayLine(entry) + "\n").utf8))
                }
            }
        } catch let error as SxError {
            stderr.write(Data("sx: \(error.message)\n".utf8))
            throw ExitCode(error.exitCode.rawValue)
        }
    }
}

// MARK: - HistoryClear

/// The `sx history clear` subcommand — delete all search history.
///
/// Deletes the history file if it exists (absent file is not an error).
/// A status confirmation is written to stderr. Any ``SxError`` is written to
/// stderr and re-thrown as the appropriate exit code.
public struct HistoryClear: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Delete all search history."
    )

    public init() {}

    // MARK: run

    public func run() async throws {
        let stderr = Shell.current.stderr

        do {
            try await History.clear()
            stderr.write(Data("sx: search history cleared\n".utf8))
        } catch let error as SxError {
            stderr.write(Data("sx: \(error.message)\n".utf8))
            throw ExitCode(error.exitCode.rawValue)
        }
    }
}
