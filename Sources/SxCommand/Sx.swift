import ArgumentParser
import Foundation
import ShellKit
import SwiftSx

/// The root `sx` command — a multi-engine web search tool built for LLM agents.
///
/// The search pipeline (config, backends, manager, rendering) lands across the
/// PRs listed in `AGENTS.md`. This skeleton wires up the command surface,
/// `--version`, and `--help`; `run()` fails closed until the pipeline is in.
public struct Sx: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sx",
        abstract: "Multi-engine web search for LLM agents (a Swift port of byteowlz/sx).",
        discussion: """
        Queries SearXNG, Brave, Tavily, Exa, or Jina with automatic failover. \
        Output is built for programmatic use: machine data on stdout, \
        diagnostics on stderr, stable exit codes, and a --json mode.
        """,
        version: SxVersion.current
    )

    @Argument(help: "The search query (one or more terms).")
    public var query: [String] = []

    public init() {}

    public func run() async throws {
        // Skeleton: fail closed with an actionable message rather than
        // pretending to succeed. The pipeline is being ported — see AGENTS.md.
        Shell.current.stderr.write(Data(
            "sx: not yet implemented in this build — the search pipeline is being ported (see AGENTS.md roadmap)\n".utf8))
        throw ExitCode(SxExitCode.general.rawValue)
    }
}
