import ArgumentParser
import Foundation
import ShellKit
import SwiftSx

/// The root `sx` command — a multi-engine web search tool built for LLM agents.
///
/// Loads the (sandboxed) config, builds the backend registry + manager, runs the
/// query (with fallback, or against a single `--engine`), and renders the
/// results: machine data on stdout, diagnostics on stderr, stable exit codes,
/// and a `--json` mode that is always valid JSON.
public struct Sx: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sx",
        abstract: "Multi-engine web search for LLM agents (a Swift port of byteowlz/sx).",
        discussion: """
        Queries SearXNG, Brave, Tavily, Exa, or Jina with automatic failover. \
        Output is built for programmatic use: machine data on stdout, \
        diagnostics on stderr, stable exit codes, and a --json mode.
        """,
        version: SxVersion.current,
        subcommands: [HistoryCommand.self]
    )

    // MARK: Arguments

    @Argument(help: "The search query (one or more terms; use - to read the query from stdin).")
    public var query: [String] = []

    // MARK: Engine selection

    @Option(name: [.short, .long],
            help: "Use a single engine with no fallback (searxng, brave, tavily, exa, jina).")
    public var engine: String?

    // MARK: Output format

    @Flag(name: .long, help: "Output results as a JSON envelope.")
    public var json: Bool = false

    @Flag(name: .long, help: "Output compact JSON, omitting empty/zero fields (implies --json).")
    public var clean: Bool = false

    @Flag(name: .long, help: "Output result URLs only, one per line.")
    public var links: Bool = false

    @Flag(name: .long, help: "Fetch each result page and output its raw HTML (overrides the format flags).")
    public var html: Bool = false

    @Flag(name: .long, help: "Fetch each result page and output its main content as Markdown (overrides the format flags; wins over --html).")
    public var text: Bool = false

    // MARK: Query tuning

    @Option(name: [.customShort("n"), .customLong("count")],
            help: "Maximum number of results to return.")
    public var count: Int?

    @Option(name: .long, help: "Restrict results to a site or domain, e.g. github.com.")
    public var site: String?

    @Option(name: .customLong("time-range"),
            help: "Recency filter passed to the engine: day, week, month, or year.")
    public var timeRange: String?

    @Option(name: [.customShort("p"), .long], help: "1-indexed result page.")
    public var page: Int?

    @Option(name: .customLong("safe-search"),
            help: "Safe-search level: strict, moderate, or off.")
    public var safeSearch: String?

    @Option(name: [.customShort("c"), .customLong("category")],
            help: "Result category (repeatable), e.g. general, news, images.")
    public var category: [String] = []

    @Option(name: [.customShort("l"), .long], help: "Language/locale code, e.g. en-US.")
    public var language: String?

    // MARK: Output destination

    @Option(name: [.customShort("o"), .long],
            help: "Write results to a file (via the sandbox) instead of stdout.")
    public var output: String?

    // MARK: Plain-output UX

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colour in plain output.")
    public var noColor: Bool = false

    @Flag(name: .long, help: "Show the full URL beneath each result (plain output).")
    public var expand: Bool = false

    @Flag(name: .long, help: "Output only the top result.")
    public var first: Bool = false

    // MARK: Behaviour

    @Flag(name: .customLong("dry-run"),
          help: "Print the resolved search plan and exit, without querying.")
    public var dryRun: Bool = false

    @Flag(name: .customLong("fail-empty"),
          help: "Exit with code 4 if the search returns no results.")
    public var failEmpty: Bool = false

    public init() {}

    // MARK: - Pure helpers (testable without I/O)

    /// Whether the query should be read from standard input — the `-` argument
    /// convention (`echo "swift concurrency" | sx -`).
    var readsQueryFromStdin: Bool { query == ["-"] }

    /// Builds the ``SearchOptions`` for this invocation by overlaying the parsed
    /// flags onto the config's defaults. Pure (no validation, no I/O) so it can be
    /// reused by `--dry-run` and unit-tested directly.
    ///
    /// - Parameter queryOverride: When non-nil, used as the query instead of the
    ///   joined positional arguments (the command supplies the stdin text here
    ///   for `sx -`).
    func searchOptions(from config: Config, queryOverride: String? = nil) -> SearchOptions {
        var options = config.baseSearchOptions()
        let rawQuery = queryOverride ?? query.joined(separator: " ")
        options.query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let count = count { options.numResults = count }
        if let site = site { options.site = site }
        if let timeRange = timeRange { options.timeRange = timeRange }
        if let page = page { options.pageNo = page }
        if let safeSearch = safeSearch { options.safeSearch = safeSearch }
        if !category.isEmpty { options.categories = category }
        if let language = language { options.language = language }
        return options
    }

    /// Builds and validates the ``SearchOptions`` for this invocation.
    ///
    /// Rejects the unambiguously-wrong inputs an agent can fix from the message:
    /// an empty query and a non-positive `--page`. Other tuning values are left
    /// for the backends to interpret (they vary by engine).
    ///
    /// - Throws: ``SxError`` with code `.usage` for an empty query or `page < 1`.
    func validatedSearchOptions(from config: Config, queryOverride: String? = nil) throws -> SearchOptions {
        let options = searchOptions(from: config, queryOverride: queryOverride)
        guard !options.query.isEmpty else {
            throw SxError(.usage, "no query given — pass search terms (e.g. sx \"swift concurrency\") or pipe them via sx -")
        }
        guard options.pageNo >= 1 else {
            throw SxError(.usage, "--page must be 1 or greater (got \(options.pageNo))")
        }
        if let count = count, count < 1 {
            throw SxError(.usage, "--count must be 1 or greater (got \(count))")
        }
        return options
    }

    /// Validates flag-only inputs that depend on neither config nor stdin, so the
    /// command can reject them (usage, exit 2) before any I/O — crucially before
    /// reading stdin for `sx -`, which can block on an open pipe/TTY. Pure, so it
    /// is unit-testable directly.
    ///
    /// - Throws: ``SxError`` with code `.usage` for a non-positive `--count` /
    ///   `--page`, or for `--html`/`--text` combined with `--json`/`--clean`
    ///   (raw page bodies would break the "`--json` is always valid JSON" contract).
    func validateFlags() throws {
        if let count = count, count < 1 {
            throw SxError(.usage, "--count must be 1 or greater (got \(count))")
        }
        if let page = page, page < 1 {
            throw SxError(.usage, "--page must be 1 or greater (got \(page))")
        }
        if (html || text) && (json || clean) {
            throw SxError(.usage, "--html/--text cannot be combined with --json/--clean (fetched page content is not JSON)")
        }
    }

    /// Renders the `--dry-run` plan: a deterministic, human-readable summary of
    /// what *would* be searched, written to stdout. No network occurs.
    static func dryRunPlan(
        engine: String?,
        config: Config,
        options: SearchOptions,
        format: OutputFormat,
        html: Bool = false,
        text: Bool = false
    ) -> String {
        var lines = ["sx dry-run — no query sent"]
        if let engine = engine {
            lines.append("  engine:     \(engine) (explicit, no fallback)")
        } else {
            lines.append("  engine:     \(config.engine)")
            if !config.fallbackEngines.isEmpty {
                lines.append("  fallbacks:  \(config.fallbackEngines.joined(separator: ", "))")
            }
        }
        lines.append("  query:      \(options.query)")
        lines.append("  results:    \(options.numResults)")
        if !options.site.isEmpty {
            lines.append("  site:       \(options.site)")
        }
        if !options.timeRange.isEmpty {
            lines.append("  time-range: \(options.timeRange)")
        }
        if options.pageNo != 1 {
            lines.append("  page:       \(options.pageNo)")
        }
        if !options.categories.isEmpty {
            lines.append("  categories: \(options.categories.joined(separator: ", "))")
        }
        if !options.language.isEmpty {
            lines.append("  language:   \(options.language)")
        }
        if !options.safeSearch.isEmpty {
            lines.append("  safe-search: \(options.safeSearch)")
        }
        // --html/--text override the result-list format and fetch each result page,
        // so report the actual content mode rather than the unrelated format label.
        if text {
            lines.append("  format:     text (fetch each result page → Markdown)")
        } else if html {
            lines.append("  format:     html (fetch each result page → raw HTML)")
        } else {
            lines.append("  format:     \(format.label)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Applies `--first`: keeps only the top result when set, otherwise all.
    func selectedResults(_ results: [SearchResult]) -> [SearchResult] {
        first ? Array(results.prefix(1)) : results
    }

    // MARK: - Output

    /// Writes the rendered results to the `--output` file (gated through the
    /// ShellKit sandbox) or, by default, to stdout. A successful file write is
    /// confirmed on stderr so the caller knows the data did not go to stdout.
    ///
    /// - Throws: ``SxError`` with code `.refused` when the sandbox denies access,
    ///   or `.general` when the file write fails.
    func emitResults(_ text: String) async throws {
        let data = Data(text.utf8)
        guard let output = output else {
            Shell.current.stdout.write(data)
            return
        }
        let url = Shell.resolve(output)
        do {
            try await Shell.authorize(url)
        } catch {
            throw SxError(.refused, "cannot write output to \(output): \(error)")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SxError(.general, "cannot write output file at \(output): \(error)")
        }
        Shell.current.stderr.write(Data("sx: wrote results to \(output)\n".utf8))
    }

    // MARK: - Content fetch (--html)

    /// Fetches each result's page concurrently, preserving input order.
    ///
    /// A per-page failure other than a sandbox refusal or cancellation yields
    /// `nil` for that page rather than aborting the whole command — one
    /// unreachable result shouldn't sink the rest.
    func fetchPages(_ results: [SearchResult], using fetcher: PageFetcher) async throws -> [String?] {
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (index, result) in results.enumerated() {
                group.addTask {
                    do {
                        return (index, try await fetcher.fetch(result.url))
                    } catch let sxError as SxError where sxError.exitCode == .refused || sxError.exitCode == .auth {
                        throw sxError            // sandbox denial (3) or no-network (7): fail-closed, not a per-page skip
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Defence in depth: surface cancellation even if it
                        // arrived as a transport error (PageFetcher already maps
                        // URLError.cancelled → CancellationError).
                        if Task.isCancelled { throw CancellationError() }
                        return (index, nil)      // skip a single unreachable page
                    }
                }
            }
            var bodies = [String?](repeating: nil, count: results.count)
            for try await (index, body) in group {
                bodies[index] = body
            }
            return bodies
        }
    }

    /// Fetches each result's page and renders the document, emitting a stderr note
    /// for any page that couldn't be fetched.
    ///
    /// - Parameter asText: when `true`, each fetched body is run through
    ///   ``HTMLExtractor`` (raw HTML → Markdown); otherwise the raw HTML is kept.
    func renderFetchedPages(_ results: [SearchResult], asText: Bool, using fetcher: PageFetcher) async throws -> String {
        let bodies = try await fetchPages(results, using: fetcher)
        let stderr = Shell.current.stderr
        for (result, body) in zip(results, bodies) where body == nil {
            stderr.write(Data("sx: could not fetch \(PageFetcher.redacted(result.url))\n".utf8))
        }
        return Self.renderPages(results, contents: Self.pageContents(bodies, asText: asText))
    }

    /// Maps fetched raw bodies to the content to display: extracted Markdown
    /// (`asText`) via ``HTMLExtractor`` or the raw HTML otherwise. `nil` (an
    /// unreachable page) is preserved. Pure (no I/O) so it is unit-testable.
    static func pageContents(_ bodies: [String?], asText: Bool) -> [String?] {
        bodies.map { body in
            guard let body else { return nil }
            return asText ? HTMLExtractor.extract(body) : body
        }
    }

    /// Renders fetched page content as one document — a titled block per result
    /// (heading + URL + content), separated by `---`. `nil` content (an
    /// unreachable page) becomes an inline note. Pure (no I/O) so it is
    /// unit-testable.
    static func renderPages(_ results: [SearchResult], contents: [String?]) -> String {
        var blocks: [String] = []
        for (result, content) in zip(results, contents) {
            let heading = result.title.isEmpty ? result.url : result.title
            let block = "# \(heading)\n\(result.url)\n\n"
                + (content ?? "(sx: could not fetch this page)")
            blocks.append(block)
        }
        return blocks.joined(separator: "\n\n---\n\n") + "\n"
    }

    // MARK: - Input

    /// Reads the whole query from standard input (for the `sx -` convention).
    ///
    /// Routed through ShellKit's `Shell.current.stdin` rather than the host process's
    /// fd 0, so `echo … | sx -` reads the correct stream when `sx` runs as an
    /// in-process builtin under SwiftPorts/SwiftBash (where stdin is ShellKit's
    /// virtual pipe), not only as a standalone CLI — mirroring the stdout/stderr usage.
    static func readStandardInput() async -> String {
        await Shell.current.stdin.readAllString()
    }

    // MARK: - Run

    public func run() async throws {
        let stdout = Shell.current.stdout
        let stderr = Shell.current.stderr

        do {
            // Reject user-fixable bad FLAG input BEFORE any I/O — including reading
            // stdin, which can block on an open pipe/TTY — so the agent always gets
            // the usage exit code (2) immediately rather than hanging or hitting a
            // config/sandbox error.
            try validateFlags()

            // Resolve the query (this may read stdin for `sx -`) and reject an empty
            // one — done after the flag checks above so a bad flag never blocks here.
            let queryOverride = readsQueryFromStdin ? await Self.readStandardInput() : nil
            guard !(queryOverride ?? query.joined(separator: " "))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SxError(.usage, "no query given — pass search terms (e.g. sx \"swift concurrency\") or pipe them via sx -")
            }

            let config = try await Config.load()
            let options = try validatedSearchOptions(from: config, queryOverride: queryOverride)

            let format = OutputFormat.resolve(
                json: json, clean: clean, links: links, configDefault: config.defaultOutput
            )

            // --dry-run: print the plan and stop before building backends or
            // making any network call — a pure, side-effect-free preview.
            if dryRun {
                stdout.write(Data(Self.dryRunPlan(
                    engine: engine, config: config, options: options,
                    format: format, html: html, text: text
                ).utf8))
                return
            }

            // An explicit --engine must work even if the config's default/fallback
            // engines are misconfigured, so build a manager whose primary IS the
            // requested engine rather than validating the whole config.
            let outcome: SearchOutcome
            if let engine = engine {
                let manager = try SearchManager(
                    registry: SearchManager.makeRegistry(from: config),
                    primary: engine, fallbacks: []
                )
                outcome = try await manager.searchExplicit(engine, options)
            } else {
                let manager = try SearchManager.make(from: config)
                outcome = try await manager.search(options)
            }

            // Drop URL-less results (e.g. a Tavily answer stub) in modes that need a
            // URL — before --first — so they keep the top *usable* result.
            let needsURL = html || text || format == .links
            let base = needsURL ? outcome.results.filter { !$0.url.isEmpty } : outcome.results
            let results = selectedResults(base)
            let rendered: String
            if html || text {
                // Content mode: fetch each page and output its content — extracted
                // Markdown (--text, which wins) or raw HTML (--html). Overrides the
                // JSON/links/plain format flags.
                rendered = try await renderFetchedPages(
                    results, asText: text, using: PageFetcher(timeout: config.timeout)
                )
            } else {
                switch format {
                case .json(let clean):
                    rendered = try ResultRenderer.renderJSON(
                        query: options.query, results: results, clean: clean
                    )
                case .links:
                    rendered = ResultRenderer.renderLinks(results)
                case .plain:
                    // Colour is suppressed by --no-color or the config's no_color.
                    rendered = ResultRenderer.renderPlain(
                        query: options.query, results: results,
                        expand: expand, noColor: noColor || config.noColor
                    )
                }
            }
            try await emitResults(rendered)

            // Record history. Non-fatal: the search already succeeded and its
            // output was written, so a history failure is a note, not an error.
            do {
                try await History.append(query: options.query, config: config)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = (error as? SxError)?.message ?? "\(error)"
                stderr.write(Data("sx: note: history not recorded — \(message)\n".utf8))
            }

            // Always note empty results so an agent can tell an empty search from a
            // silent/broken one; --fail-empty additionally sets exit code 4.
            if results.isEmpty {
                stderr.write(Data("sx: no results for query: \(options.query)\n".utf8))
                if failEmpty {
                    throw ExitCode(SxExitCode.empty.rawValue)
                }
            }
        } catch let error as SxError {
            stderr.write(Data("sx: \(error.message)\n".utf8))
            throw ExitCode(error.exitCode.rawValue)
        }
    }
}
