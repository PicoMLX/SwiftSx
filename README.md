# SwiftSx

A Swift port of [`sx`](https://github.com/byteowlz/sx) — multi-engine web search from the command line.

SwiftSx brings `sx`'s multi-backend search to the Swift ecosystem as a reusable
library. Like the original Go tool, it queries one or more search backends —
SearXNG, Exa, Jina, Brave Search, and Tavily — with automatic fallback when the
primary engine is unavailable.

> **Status:** Early work in progress. The package scaffolding is in place; the
> API is still being ported and is subject to change.

## About the original `sx`

[`sx`](https://github.com/byteowlz/sx) by [byteowlz](https://github.com/byteowlz)
is a Go CLI that lets you search the web from your terminal across multiple
engines with automatic failover. Highlights:

- **Multiple backends with automatic failover** — SearXNG (self-hosted), Exa,
  Jina, Brave Search, and Tavily
- **Search categories** — news, images, videos, files
- **Filtering** — safe search and time-range options
- **Scriptable** — JSON output
- **Content extraction** — convert results to Markdown
- **Quality of life** — query history, shell completions, and interactive mode
- **Cross-platform** — macOS, Linux, Windows

Example `sx` usage, for reference:

```sh
sx "swift concurrency"                 # basic search
sx "swift concurrency" --engine exa    # pick an engine
sx "swift concurrency" -L              # links only
sx "swift concurrency" --text          # extract page content as Markdown
sx history                             # show query history
```

## Installation

Add SwiftSx to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PicoMLX/SwiftSx.git", branch: "main")
]
```

Then add it to a target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftSx"]
)
```

Requires the Swift 6.3 toolchain (Swift language mode v6).

## Usage

```swift
import SwiftSx

// API coming soon — see Status above.
```

## Credits

SwiftSx is a Swift port of [`sx`](https://github.com/byteowlz/sx) by
[byteowlz](https://github.com/byteowlz), used under the MIT License.

## License

MIT. See [LICENSE](LICENSE).
