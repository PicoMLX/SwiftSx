/// The output mode for a search, resolved from CLI flags and the config default.
enum OutputFormat: Equatable {
    /// JSON envelope. `clean` omits empty/zero/`nil`/empty-collection fields.
    case json(clean: Bool)
    /// One result URL per line.
    case links
    /// Human-readable, optionally coloured.
    case plain

    /// A short label for the format, used in `--dry-run` output.
    var label: String {
        switch self {
        case .json(let clean): return clean ? "json (clean)" : "json"
        case .links:           return "links"
        case .plain:           return "plain"
        }
    }

    /// Resolve the output format.
    ///
    /// Explicit flags take precedence over the config default. Among flags the
    /// precedence is `--clean` > `--json` > `--links` (so `--clean` always means
    /// clean JSON, even if `--json` is also passed). With no flags, the config's
    /// `default_output` is consulted; an unrecognised value falls back to plain.
    ///
    /// - Parameters:
    ///   - json: The `--json` flag.
    ///   - clean: The `--clean` flag (implies JSON).
    ///   - links: The `--links` flag.
    ///   - configDefault: `config.defaultOutput` (e.g. `""`, `"json"`, `"links"`).
    /// - Returns: The resolved ``OutputFormat``.
    static func resolve(json: Bool, clean: Bool, links: Bool, configDefault: String) -> OutputFormat {
        if clean { return .json(clean: true) }
        if json  { return .json(clean: false) }
        if links { return .links }

        switch configDefault.lowercased() {
        case "json":                 return .json(clean: false)
        case "clean", "json-clean":  return .json(clean: true)
        case "links":                return .links
        default:                     return .plain
        }
    }
}
