# Agent instructions — SwiftSx

A pure-Swift, cross-platform port of [`byteowlz/sx`](https://github.com/byteowlz/sx) —
a multi-engine web-search CLI (SearXNG, Brave, Tavily, Exa, Jina) with automatic
failover. SwiftSx is built to be **driven by LLM agents**, so its output, error
messages, and exit codes are designed to be machine-actionable, and all file
access is mediated by a host sandbox.

It follows the conventions of the [SwiftPorts](https://github.com/PicoMLX/SwiftPorts)
monorepo, and consumes [Cocoanetics/ShellKit](https://github.com/Cocoanetics/ShellKit)
for its virtualised shell environment (sandboxed filesystem, environment
variables, stdio).

## Layout

A single library + binary port, flat (this repo hosts one tool):

```
Sources/
  SwiftSx/        SDK library  — models, config, backends, manager, rendering.
                  No ArgumentParser. Uses ShellKit (sandbox/env) and, once the
                  backends land, swift-http-types.
  SxCommand/      Command library — the `sx` AsyncParsableCommand tree.
                  Depends on SwiftSx + ShellKit + ArgumentParser.
  sx/             Executable — a ~4-line @main wrapper over SxCommand.
Tests/
  SwiftSxTests/   SDK tests (models, config, backends w/ URLProtocol mocks, manager).
  SxCommandTests/ argv parsing + end-to-end command tests.
```

Dependency chain is one-way: `sx` (exec) → `SxCommand` → `SwiftSx` → `ShellKit`.
The SDK library has **zero** ArgumentParser dependency so other packages
(SwiftBash) can import `SxCommand` and register the tool as a builtin.

Third-party dependencies are introduced in the PR that first needs them, so
each stacked PR stays small: `ShellKit` + `swift-argument-parser` arrive with
the command skeleton, the TOML parser with config loading, and
`swift-http-types` with the search backends.

## The file sandbox (ShellKit)

SwiftSx never touches the filesystem or process environment directly. Every
path the user/agent supplies is routed through ShellKit's gate, and every
environment read (API keys included) goes through `Shell.env`:

```swift
import ShellKit

let url = Shell.resolve(path)          // String → URL, cwd/sandbox-aware
do { try await Shell.authorize(url) }  // throws SandboxingError if denied
catch { /* map to a "sx: …" message + exit 3 (refused) */ }
// only now read/write the file at `url`

let key = Shell.env("EXA_API_KEY")     // never ProcessInfo.processInfo.environment
```

Output streams follow the LLM-friendly split:
- **machine data → stdout** via `Shell.current.stdout.write(_:)` (JSON, links, results)
- **diagnostics → stderr** via `Shell.current.stderr.write(_:)` ("no results", hints, errors)

Files SwiftSx may read/write (all sandbox-gated):
- config: `$XDG_CONFIG_HOME/sx/config.toml` (default `~/.config/sx/config.toml`)
- history: `$XDG_STATE_HOME/sx/history` (default `~/.local/state/sx/history`)
- `--output <path>`: where results are written when requested

## Conventions (inherited from SwiftPorts)

- **Models are `Codable` structs, one type per file.** Decoders configured via
  factory helpers (snake_case ↔ camelCase per backend).
- **ArgumentParser** lives only in `SxCommand`. `AsyncParsableCommand` for
  anything doing I/O.
- **Swift Testing** (`@Test`, `#expect`, `#require`) — not XCTest.
- **HTTP via `swift-http-types` + `URLSession`**, mocked in tests with a
  `URLProtocol` subclass on a custom `URLSessionConfiguration`. No live network
  in tests.
- **No `Process` shellouts.** (This is why browser-opening is dropped — see below.)
- File basenames unique within a target; `Type+Concern.swift` for extensions.

## LLM-friendly messages & exit codes

This CLI is consumed by agents, so `llm-friendly-cli-messages` rules are
mandatory: every error names a concrete next action (the flag, env var, config
key, or scope to fix), messages are prefixed `sx:`, data is deterministic and
stable, secrets never appear in output, and `--json` always prints valid JSON
(an empty `[]` rather than silence).

Exit-code scheme (stable; agents branch on it):

| code | meaning |
|------|---------|
| 0 | success |
| 1 | general / unclassified runtime error |
| 2 | usage / bad input — the agent can fix the command |
| 3 | refused by policy / sandbox gate — not a retry |
| 4 | empty results **and** `--fail-empty` was set |
| 7 | fail-closed: missing/invalid auth or no network — escalate, don't retry |

Backend errors map onto these: auth (401/403) → 7, rate-limit (429) → message
saying "back off and retry", not-configured → 7 naming the env var/key to set,
malformed response → 1.

## Deviations from Go `sx` (agent-focused)

Documented here so they're reviewable. The Go tool targets humans at a TTY;
SwiftSx targets agents:

- **Dropped: interactive mode (`-i`)** — there is no human at a prompt.
- **Dropped: browser-opening (`--lucky`, `url_handler`, opening result URLs)** —
  meaningless to an agent and would require a `Process` shellout (forbidden).
  **`--first` is repurposed** to "return only the top result".
- **Dropped: interactive config bootstrap (`ensureConfig` prompt)** — agents
  can't answer prompts. A missing `config.toml` is **not** itself an error
  (`Config.load()` returns defaults), so e.g. `sx --engine brave …` with
  `BRAVE_API_KEY` set works with no config file. Instead the tool **fails
  closed at search time**: if the selected engine isn't configured it exits `7`
  with a message naming the env var / config key to set. A non-interactive
  `sx config init` may write a template later.
- **Strengthened: errors & exit codes** as above; added `--fail-empty` and
  `--dry-run` (print the request that would be sent without sending it).
- **Deferred: `--text` (readability → Markdown) and `--html` (raw fetch with
  anti-bot headers)** — the heaviest pieces to port; they land in later PRs and
  may ship simplified.

## Backends

Five backends behind one `SearchBackend` protocol, selected by `engine` with an
ordered `fallback_engines` chain (or one-shot via `--engine`):

| engine | endpoint | auth (env overrides config) |
|--------|----------|-----------------------------|
| `searxng` | `<url>/search` (GET/POST, optional Basic auth; multi-instance ordered / parallel-fastest) | — |
| `brave` | `api.search.brave.com/res/v1/web/search` | `BRAVE_API_KEY` → header `X-Subscription-Token` |
| `tavily` | `api.tavily.com/search` (POST) | `TAVILY_API_KEY` → `Authorization: Bearer` |
| `exa` | `api.exa.ai/search` (POST) + MCP JSON-RPC mode | `EXA_API_KEY` → header `x-api-key` |
| `jina` | `s.jina.ai` (POST, keyless allowed) | `JINA_API_KEY` → `Authorization: Bearer` |

## Build, test, run

```bash
swift build
swift test
swift run sx "swift concurrency"        # once wired up
```

CI (`.github/workflows/swift.yml`) builds + tests on macOS (Xcode 26.4.1 /
Swift 6.3) and Linux (`swift:6.3-noble`) on every push and PR into `main`.

## PR roadmap

Small, stacked PRs, each green on CI:

1. **Package skeleton + this AGENTS.md + core models + `--version`/`--help`** ← you are here
2. Config model + TOML loading (sandboxed) + env-var key overrides
3. Backend protocol + manager (primary→fallback) + error→exit-code + HTTP/mock harness
4. SearXNG backend (single + multi-instance strategies)
5. Brave + Tavily backends
6. Exa (API + MCP) + Jina backends
7. History (sandboxed) + `history` / `history clear`
8. Output rendering: JSON / `--clean` / links-only / plain + categories
9. Wire the root command end-to-end (flags → manager → output, stdin, `--output`, `--dry-run`)
10. `completion` subcommand
11. (later) `--text` extraction · (later) `--html`

## SwiftBash consumption

SwiftBash registers the whole tree as a Bash builtin via a one-line conformance
against the `SxCommand` library (the conformance lives in SwiftBash, the
implementation here — no cycle):

```swift
import SxCommand
extension Sx: ParsableBashCommand { … }
```
