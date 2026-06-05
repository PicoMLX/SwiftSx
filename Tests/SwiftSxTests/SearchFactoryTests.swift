import Testing
@testable import SwiftSx

// MARK: - SearchManager.make(from:)

@Suite struct SearchManagerFactoryTests {

    @Test func knownEnginesAreTheFiveBackends() {
        #expect(SearchManager.knownEngines == ["searxng", "brave", "tavily", "exa", "jina"])
    }

    @Test func defaultConfigBuildsManager() throws {
        // Default config: primary "searxng", no fallbacks.
        _ = try SearchManager.make(from: Config())
    }

    @Test func everyKnownEngineIsRegistered() throws {
        // If any engine were missing from the registry, using it as the primary
        // would throw .usage. Succeeding for all five proves registry membership.
        for engine in SearchManager.knownEngines {
            _ = try SearchManager.make(from: Config(engine: engine))
        }
    }

    @Test func validFallbackChainBuildsManager() throws {
        let config = Config(engine: "brave", fallbackEngines: ["searxng", "jina", "exa", "tavily"])
        _ = try SearchManager.make(from: config)
    }

    @Test func unknownPrimaryThrowsUsage() {
        do {
            _ = try SearchManager.make(from: Config(engine: "bogus"))
            Issue.record("expected make(from:) to throw for an unknown primary engine")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        } catch {
            Issue.record("expected SxError, got \(error)")
        }
    }

    @Test func unknownFallbackThrowsUsage() {
        let config = Config(engine: "searxng", fallbackEngines: ["brave", "nope"])
        do {
            _ = try SearchManager.make(from: config)
            Issue.record("expected make(from:) to throw for an unknown fallback engine")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        } catch {
            Issue.record("expected SxError, got \(error)")
        }
    }
}

// MARK: - Config.baseSearchOptions()

@Suite struct ConfigBaseSearchOptionsTests {

    @Test func defaultsMapToEmptyBaselineWithResultCount() {
        let opts = Config().baseSearchOptions()
        #expect(opts.query == "")
        #expect(opts.categories.isEmpty)
        #expect(opts.engines.isEmpty)
        #expect(opts.language == "")
        #expect(opts.timeRange == "")
        #expect(opts.site == "")
        #expect(opts.safeSearch == "strict")
        #expect(opts.pageNo == 1)
        #expect(opts.numResults == 10)
    }

    @Test func configFieldsPropagate() {
        let config = Config(
            resultCount: 25,
            categories: ["news", "general"],
            safeSearch: "off",
            engines: ["google", "bing"],
            language: "en-US"
        )
        let opts = config.baseSearchOptions()
        #expect(opts.categories == ["news", "general"])
        #expect(opts.engines == ["google", "bing"])
        #expect(opts.language == "en-US")
        #expect(opts.safeSearch == "off")
        #expect(opts.numResults == 25)
        // Per-invocation fields stay at their defaults for the command to overlay.
        #expect(opts.pageNo == 1)
        #expect(opts.query == "")
        #expect(opts.site == "")
        #expect(opts.timeRange == "")
    }
}
