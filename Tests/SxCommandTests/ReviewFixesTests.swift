import Testing
import SwiftSx
@testable import SxCommand

@Suite struct ReviewFixesTests {

    @Test func negativeCountIsUsageError() throws {
        do {
            _ = try Sx.parse(["swift", "--count=-1"]).validatedSearchOptions(from: Config())
            Issue.record("expected a negative --count to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func zeroCountIsUsageError() throws {
        do {
            _ = try Sx.parse(["swift", "--count=0"]).validatedSearchOptions(from: Config())
            Issue.record("expected --count 0 to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func positiveCountAccepted() throws {
        let opts = try Sx.parse(["swift", "--count=3"]).validatedSearchOptions(from: Config())
        #expect(opts.numResults == 3)
    }

    @Test func dryRunPlanShowsSafeSearch() throws {
        let opts = try Sx.parse(["q", "--safe-search", "off"]).searchOptions(from: Config())
        let plan = Sx.dryRunPlan(engine: nil, config: Config(), options: opts, format: .plain)
        #expect(plan.contains("safe-search:"))
        #expect(plan.contains("off"))
    }

    @Test func makeRegistryHasAllKnownEngines() {
        let registry = SearchManager.makeRegistry(from: Config())
        #expect(Set(registry.keys) == Set(SearchManager.knownEngines))
    }

    // --html/--text emit raw page bodies, so combining them with --json/--clean
    // would break the "--json is always valid JSON" contract → usage (exit 2).
    @Test func htmlWithJsonIsUsageError() throws {
        do {
            try Sx.parse(["swift", "--html", "--json"]).validateFlags()
            Issue.record("expected --html --json to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func textWithCleanIsUsageError() throws {
        do {
            try Sx.parse(["swift", "--text", "--clean"]).validateFlags()
            Issue.record("expected --text --clean to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func contentModesWithoutJsonAreAccepted() throws {
        // Each of these is a valid combination and must not throw.
        try Sx.parse(["swift", "--html"]).validateFlags()
        try Sx.parse(["swift", "--text"]).validateFlags()
        try Sx.parse(["swift", "--json"]).validateFlags()
        try Sx.parse(["swift", "--html", "--links"]).validateFlags()
    }

    @Test func nonPositivePageIsUsageErrorInValidateFlags() throws {
        do {
            try Sx.parse(["swift", "--page=0"]).validateFlags()
            Issue.record("expected --page 0 to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }
}
