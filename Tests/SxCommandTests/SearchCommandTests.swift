import Testing
import SwiftSx
@testable import SxCommand

// MARK: - OutputFormat.resolve

@Suite struct OutputFormatTests {

    @Test func cleanFlagResolvesToCleanJSON() {
        #expect(OutputFormat.resolve(json: false, clean: true, links: false, configDefault: "") == .json(clean: true))
    }

    @Test func jsonFlagResolvesToJSON() {
        #expect(OutputFormat.resolve(json: true, clean: false, links: false, configDefault: "") == .json(clean: false))
    }

    @Test func linksFlagResolvesToLinks() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: true, configDefault: "") == .links)
    }

    @Test func cleanBeatsJsonAndLinks() {
        #expect(OutputFormat.resolve(json: true, clean: true, links: true, configDefault: "") == .json(clean: true))
    }

    @Test func jsonBeatsLinks() {
        #expect(OutputFormat.resolve(json: true, clean: false, links: true, configDefault: "") == .json(clean: false))
    }

    @Test func configDefaultJSONUsedWhenNoFlags() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "json") == .json(clean: false))
    }

    @Test func configDefaultCleanUsedWhenNoFlags() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "clean") == .json(clean: true))
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "json-clean") == .json(clean: true))
    }

    @Test func configDefaultLinksUsedWhenNoFlags() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "links") == .links)
    }

    @Test func emptyConfigDefaultIsPlain() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "") == .plain)
    }

    @Test func unknownConfigDefaultIsPlain() {
        #expect(OutputFormat.resolve(json: false, clean: false, links: false, configDefault: "weird") == .plain)
    }

    @Test func flagsOverrideConfigDefault() {
        // --links wins even though the config default is json.
        #expect(OutputFormat.resolve(json: false, clean: false, links: true, configDefault: "json") == .links)
    }

    @Test func labels() {
        #expect(OutputFormat.json(clean: false).label == "json")
        #expect(OutputFormat.json(clean: true).label == "json (clean)")
        #expect(OutputFormat.links.label == "links")
        #expect(OutputFormat.plain.label == "plain")
    }
}

// MARK: - Flag parsing + searchOptions overlay

@Suite struct SearchCommandParsingTests {

    @Test func parsesOutputAndBehaviourFlags() throws {
        let cmd = try Sx.parse([
            "q", "--json", "--dry-run", "--fail-empty", "--no-color", "--expand",
            "-e", "brave", "-n", "3",
        ])
        #expect(cmd.query == ["q"])
        #expect(cmd.json)
        #expect(cmd.dryRun)
        #expect(cmd.failEmpty)
        #expect(cmd.noColor)
        #expect(cmd.expand)
        #expect(cmd.engine == "brave")
        #expect(cmd.count == 3)
    }

    @Test func defaultsAreUnset() throws {
        let cmd = try Sx.parse(["hello"])
        #expect(!cmd.json)
        #expect(!cmd.clean)
        #expect(!cmd.links)
        #expect(!cmd.dryRun)
        #expect(!cmd.failEmpty)
        #expect(cmd.engine == nil)
        #expect(cmd.count == nil)
    }

    @Test func searchOptionsJoinsQueryTerms() throws {
        let opts = try Sx.parse(["swift", "concurrency"]).searchOptions(from: Config())
        #expect(opts.query == "swift concurrency")
        #expect(opts.numResults == 10) // config default
    }

    @Test func searchOptionsCountOverridesConfig() throws {
        let opts = try Sx.parse(["foo", "-n", "5"]).searchOptions(from: Config(resultCount: 99))
        #expect(opts.numResults == 5)
        #expect(opts.query == "foo")
    }

    @Test func searchOptionsInheritsConfigResultCount() throws {
        let opts = try Sx.parse(["foo"]).searchOptions(from: Config(resultCount: 42))
        #expect(opts.numResults == 42)
    }

    @Test func searchOptionsEmptyWhenNoQuery() throws {
        let opts = try Sx.parse([]).searchOptions(from: Config())
        #expect(opts.query == "")
    }

    @Test func searchOptionsInheritsConfigDefaults() throws {
        let config = Config(categories: ["news"], safeSearch: "off", language: "en-US")
        let opts = try Sx.parse(["foo"]).searchOptions(from: config)
        #expect(opts.categories == ["news"])
        #expect(opts.safeSearch == "off")
        #expect(opts.language == "en-US")
    }
}

// MARK: - dry-run plan

@Suite struct DryRunPlanTests {

    private func options(query: String, numResults: Int = 10, categories: [String] = []) -> SearchOptions {
        var opts = SearchOptions()
        opts.query = query
        opts.numResults = numResults
        opts.categories = categories
        return opts
    }

    @Test func explicitEnginePlan() {
        let plan = Sx.dryRunPlan(
            engine: "brave",
            config: Config(),
            options: options(query: "swift", numResults: 7),
            format: .json(clean: false)
        )
        #expect(plan.contains("brave (explicit, no fallback)"))
        #expect(plan.contains("query:"))
        #expect(plan.contains("swift"))
        #expect(plan.contains("results:"))
        #expect(plan.contains("7"))
        #expect(plan.contains("format:"))
        #expect(plan.contains("json"))
        // No fallback line for an explicit engine.
        #expect(!plan.contains("fallbacks:"))
        #expect(plan.hasSuffix("\n"))
    }

    @Test func defaultEngineWithFallbacksPlan() {
        let config = Config(engine: "searxng", fallbackEngines: ["brave", "jina"])
        let plan = Sx.dryRunPlan(
            engine: nil,
            config: config,
            options: options(query: "q"),
            format: .plain
        )
        #expect(plan.contains("searxng"))
        #expect(plan.contains("fallbacks:"))
        #expect(plan.contains("brave, jina"))
        #expect(plan.contains("plain"))
    }

    @Test func cleanFormatLabelInPlan() {
        let plan = Sx.dryRunPlan(
            engine: nil,
            config: Config(),
            options: options(query: "q"),
            format: .json(clean: true)
        )
        #expect(plan.contains("json (clean)"))
    }

    @Test func categoriesShownWhenPresent() {
        let plan = Sx.dryRunPlan(
            engine: nil,
            config: Config(),
            options: options(query: "q", categories: ["news", "general"]),
            format: .plain
        )
        #expect(plan.contains("categories:"))
        #expect(plan.contains("news, general"))
    }
}
