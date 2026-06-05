import Foundation
import ShellKit
#if canImport(Glibc)
import Glibc        // open / flock / close on Linux
#elseif canImport(Darwin)
import Darwin       // open / flock / close on macOS
#endif

/// A single recorded search-history entry.
public struct HistoryEntry: Sendable, Equatable {
    /// The UTC instant at which the search was performed.
    public let timestamp: Date
    /// The raw query string that was searched.
    public let query: String

    public init(timestamp: Date, query: String) {
        self.timestamp = timestamp
        self.query = query
    }
}

// MARK: - Path

extension History {
    /// Returns the absolute path to the history file.
    ///
    /// Resolution order (XDG Base Directory spec):
    /// 1. If `XDG_STATE_HOME` is present and non-empty in `env`, use it as the
    ///    base directory.
    /// 2. Otherwise fall back to `<homeDirectory>/.local/state`.
    ///
    /// The returned path is always `<base>/sx/history`. Path components are
    /// joined via `URL` APIs so a trailing slash on the base can't produce a
    /// malformed path.
    ///
    /// - Parameters:
    ///   - env: The relevant environment variables (at least `XDG_STATE_HOME`).
    ///   - homeDirectory: The current user's home directory path string.
    /// - Returns: The absolute path to `sx/history` under the state base.
    public static func historyFilePath(
        env: [String: String],
        homeDirectory: String
    ) -> String {
        let base: URL
        if let xdg = env["XDG_STATE_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = URL(fileURLWithPath: homeDirectory)
                .appendingPathComponent(".local")
                .appendingPathComponent("state")
        }
        return base
            .appendingPathComponent("sx")
            .appendingPathComponent("history")
            .path
    }
}

// MARK: - Pure helpers

extension History {
    // MARK: ISO8601 formatter

    /// ISO 8601 / RFC 3339 formatter used for storage.
    ///
    /// Returns a fresh instance each call — `ISO8601DateFormatter` is not
    /// `Sendable` and is not thread-safe to share, so a computed property avoids
    /// both the Swift 6 concurrency-safety error and any data races.
    private static var iso8601Formatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    // MARK: Display formatter

    /// `DateFormatter` for human-readable display lines.
    ///
    /// Returns a fresh instance each call — `DateFormatter` is not `Sendable`
    /// and is not thread-safe to share, so a computed property avoids both the
    /// Swift 6 concurrency-safety error and any data races.
    private static var displayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")   // deterministic across runners
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }

    // MARK: Formatting / parsing

    /// Formats a single history entry as a tab-separated storage line.
    ///
    /// Output format: `"<RFC3339 timestamp>\t<query>\n"`. Any embedded carriage
    /// returns or line feeds in the query are collapsed to single spaces so a
    /// multi-line query can never break the one-entry-per-line format. This is
    /// the single choke point through which every stored line is produced, so
    /// the invariant holds regardless of how the entry was constructed.
    ///
    /// - Parameter entry: The entry to format.
    /// - Returns: A ready-to-append line including the trailing newline.
    public static func formatLine(_ entry: HistoryEntry) -> String {
        let iso = iso8601Formatter.string(from: entry.timestamp)
        let singleLine = entry.query
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\(iso)\t\(singleLine)\n"
    }

    /// Parses the full text of a history file into an array of entries.
    ///
    /// Each line is expected to be `"<RFC3339 timestamp>\t<query>"`. Lines that
    /// cannot be split on a tab, or whose timestamp cannot be parsed, are silently
    /// skipped. The returned array preserves the on-disk order (oldest-first).
    ///
    /// - Parameter text: The raw text content of the history file.
    /// - Returns: All valid entries found in `text`, oldest-first.
    public static func parseLines(_ text: String) -> [HistoryEntry] {
        let lines = text.components(separatedBy: "\n")
        var entries: [HistoryEntry] = []
        for line in lines {
            guard !line.isEmpty else { continue }
            // Split on the FIRST tab only so queries may contain tabs.
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let timestampStr = String(parts[0])
            let query = String(parts[1])
            guard let date = iso8601Formatter.date(from: timestampStr) else { continue }
            entries.append(HistoryEntry(timestamp: date, query: query))
        }
        return entries
    }

    /// Trims a list of raw lines to at most `maxHistory` entries, keeping the
    /// most recent (last) ones.
    ///
    /// - Parameters:
    ///   - lines: The raw storage lines (each including its trailing newline).
    ///   - maxHistory: The cap. If `<= 0`, all lines are returned unchanged.
    /// - Returns: The (possibly shorter) array of lines.
    public static func trimmed(_ lines: [String], maxHistory: Int) -> [String] {
        guard maxHistory > 0, lines.count > maxHistory else { return lines }
        return Array(lines.suffix(maxHistory))
    }

    /// Formats an entry for display in `sx history` output.
    ///
    /// Output format: `"  yyyy-MM-dd HH:mm  <query>"` (no trailing newline — the
    /// caller appends `"\n"`).
    ///
    /// - Parameter entry: The entry to format for display.
    /// - Returns: A display-ready string without a trailing newline.
    public static func displayLine(_ entry: HistoryEntry) -> String {
        let formatted = displayFormatter.string(from: entry.timestamp)
        return "  \(formatted)  \(entry.query)"
    }
}

// MARK: - Sandboxed I/O

/// Sandboxed read/write/clear operations for the search history file.
///
/// All filesystem access is mediated by the ShellKit sandbox (`Shell.resolve` +
/// `Shell.authorize`). The pure helpers on this type (path computation,
/// formatting, parsing) are testable without any I/O.
public enum History {

    // MARK: Append

    /// Appends a query to the history file, then trims if needed.
    ///
    /// This is a no-op when:
    /// - `config.historyEnabled` is `false`.
    /// - `query` is blank (whitespace-only).
    ///
    /// The `sx` subdirectory under the state base is created automatically if it
    /// does not already exist.
    ///
    /// - Parameters:
    ///   - query: The search query string to record.
    ///   - config: The active configuration (controls `historyEnabled` and
    ///     `maxHistory`).
    /// - Throws:
    ///   - ``SxError`` with code `.refused` when the sandbox denies access.
    ///   - ``SxError`` with code `.general` when a read or write fails.
    public static func append(query: String, config: Config) async throws {
        guard config.historyEnabled else { return }
        // Skip blank (whitespace-only) queries. Any internal CR/LF are collapsed
        // to spaces by `formatLine` when the storage line is produced, so they
        // cannot corrupt the one-entry-per-line history format.
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        var env: [String: String] = [:]
        if let xdg = Shell.env("XDG_STATE_HOME") { env["XDG_STATE_HOME"] = xdg }
        let home = Shell.homeDirectory.path

        let path = historyFilePath(env: env, homeDirectory: home)
        let url = Shell.resolve(path)

        do {
            try await Shell.authorize(url)
        } catch {
            throw SxError(.refused, "cannot access history file at \(path): \(error)")
        }

        // Ensure the sx/ directory exists.
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw SxError(.general, "cannot create history directory at \(dir.path): \(error)")
        }

        // Serialise concurrent `sx` processes writing the same history file:
        // hold an exclusive advisory lock (flock) on it across the whole
        // read-modify-write below, so two invocations finishing at once can't
        // interleave a stale-offset write or trim from an incomplete read.
        // Best-effort — if the lock can't be taken we still record the entry
        // rather than failing an otherwise-successful search.
        let lockFD = acquireExclusiveLock(url)
        defer { releaseLock(lockFD) }

        // Build the new line for this entry.
        let entry = HistoryEntry(timestamp: Date(), query: trimmedQuery)
        let newLine = formatLine(entry)

        if config.maxHistory > 0 {
            // Read existing content once, append in memory, trim, then write once.
            let existingText: String
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    existingText = String(decoding: data, as: UTF8.self)
                } catch {
                    throw SxError(.general, "cannot read history file at \(path): \(error)")
                }
            } else {
                existingText = ""
            }

            var allLines = existingText
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { $0 + "\n" }
            allLines.append(newLine)

            let kept = trimmed(allLines, maxHistory: config.maxHistory)
            let rewritten = kept.joined()
            do {
                try Data(rewritten.utf8).write(to: url)
            } catch {
                throw SxError(.general, "cannot write history file at \(path): \(error)")
            }
        } else {
            // No trimming needed — append the single line (create the file if absent).
            let lineData = Data(newLine.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: lineData)
                } catch {
                    throw SxError(.general, "cannot write to history file at \(path): \(error)")
                }
            } else {
                do {
                    try lineData.write(to: url)
                } catch {
                    throw SxError(.general, "cannot write history file at \(path): \(error)")
                }
            }
        }
    }

    // MARK: Advisory locking

    /// Opens the file at `url` (creating it if absent) and acquires an exclusive
    /// advisory `flock` on it.
    ///
    /// - Returns: The open file descriptor to pass to ``releaseLock(_:)``, or `-1`
    ///   if the file could not be opened (the caller then proceeds without a lock).
    static func acquireExclusiveLock(_ url: URL) -> Int32 {
        let fd = open(url.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return -1 }
        flock(fd, LOCK_EX)
        return fd
    }

    /// Releases the advisory lock held on `fd` and closes it. A negative `fd`
    /// (no lock was acquired) is a no-op.
    static func releaseLock(_ fd: Int32) {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }

    // MARK: Read

    /// Reads history entries from disk, returning the most recent `limit` entries.
    ///
    /// If the history file does not exist this returns `[]` (not an error).
    /// The returned array is ordered oldest-first.
    ///
    /// - Parameter limit: Maximum number of entries to return. `<= 0` returns all.
    /// - Returns: Up to `limit` history entries, oldest-first.
    /// - Throws:
    ///   - ``SxError`` with code `.refused` when the sandbox denies access.
    ///   - ``SxError`` with code `.general` when the file exists but cannot be read.
    public static func read(limit: Int) async throws -> [HistoryEntry] {
        var env: [String: String] = [:]
        if let xdg = Shell.env("XDG_STATE_HOME") { env["XDG_STATE_HOME"] = xdg }
        let home = Shell.homeDirectory.path

        let path = historyFilePath(env: env, homeDirectory: home)
        let url = Shell.resolve(path)

        do {
            try await Shell.authorize(url)
        } catch {
            throw SxError(.refused, "cannot access history file at \(path): \(error)")
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SxError(.general, "cannot read history file at \(path): \(error)")
        }

        let text = String(decoding: data, as: UTF8.self)
        let entries = parseLines(text)

        if limit <= 0 {
            return entries
        }
        return Array(entries.suffix(limit))
    }

    // MARK: Clear

    /// Deletes the history file if it exists.
    ///
    /// If the file is already absent this is a no-op (not an error). If a
    /// *directory* stands at the history path (a malformed store), this refuses
    /// to delete it rather than recursively removing the tree.
    ///
    /// - Throws:
    ///   - ``SxError`` with code `.refused` when the sandbox denies access.
    ///   - ``SxError`` with code `.general` when a directory stands at the path,
    ///     or when deletion fails.
    public static func clear() async throws {
        var env: [String: String] = [:]
        if let xdg = Shell.env("XDG_STATE_HOME") { env["XDG_STATE_HOME"] = xdg }
        let home = Shell.homeDirectory.path

        let path = historyFilePath(env: env, homeDirectory: home)
        let url = Shell.resolve(path)

        do {
            try await Shell.authorize(url)
        } catch {
            throw SxError(.refused, "cannot access history file at \(path): \(error)")
        }

        // Refuse to delete a directory standing at the history path: removeItem
        // would recursively delete its whole tree (including unrelated files a
        // user may have placed under a colliding `history/` directory). The
        // store is always a single file, so a directory here is a malformed
        // state the caller must resolve manually.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            throw SxError(.general, "history path is a directory, not a file: \(path) — remove it manually (the history store is a single file)")
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw SxError(.general, "cannot delete history file at \(path): \(error)")
        }
    }
}
