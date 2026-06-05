import Testing
import SwiftSx
@testable import SxCommand

@Suite struct QueryFlagsTests {

    // MARK: Parsing

    @Test func parsesAllQueryFlags() throws {
        let cmd = try Sx.parse([
            "swift",
            "--site", "github.com",
            "--time-range", "week",
            "--page", "2",
            "--safe-search", "off",
            "-c", "news", "-c", "general",
            "-l", "en-US",
        ])
        #expect(cmd.site == "github.com")
        #expect(cmd.timeRange == "week")
        #expect(cmd.page == 2)
        #expect(cmd.safeSearch == "off")
        #expect(cmd.category == ["news", "general"])
        #expect(cmd.language == "en-US")
    }

    // MARK: Overlay onto config

    @Test func overlayAppliesAllFlags() throws {
        let opts = try Sx.parse([
            "swift",
            "--site", "github.com",
            "--time-range", "week",
            "--page", "3",
            "--safe-search", "off",
            "-c", "news",
            "-l", "en-US",
        ]).searchOptions(from: Config())
        #expect(opts.query == "swift")
        #expect(opts.site == "github.com")
        #expect(opts.timeRange == "week")
        #expect(opts.pageNo == 3)
        #expect(opts.safeSearch == "off")
        #expect(opts.categories == ["news"])
        #expect(opts.language == "en-US")
    }

    @Test func overlayFallsBackToConfigWhenFlagsAbsent() throws {
        let config = Config(categories: ["images"], safeSearch: "strict", language: "fr")
        let opts = try Sx.parse(["swift"]).searchOptions(from: config)
        #expect(opts.categories == ["images"]) // from config
        #expect(opts.safeSearch == "strict")   // from config
        #expect(opts.language == "fr")          // from config
        #expect(opts.site == "")                // no flag, no config field
        #expect(opts.timeRange == "")           // no flag
        #expect(opts.pageNo == 1)               // default
    }

    @Test func categoryFlagOverridesConfigCategories() throws {
        let opts = try Sx.parse(["q", "-c", "news"]).searchOptions(from: Config(categories: ["images"]))
        #expect(opts.categories == ["news"])
    }

    // MARK: Validation

    @Test func validatedOptionsAcceptsValid() throws {
        let opts = try Sx.parse(["swift", "--page", "2"]).validatedSearchOptions(from: Config())
        #expect(opts.pageNo == 2)
        #expect(opts.query == "swift")
    }

    @Test func validatedOptionsRejectsEmptyQuery() throws {
        do {
            _ = try Sx.parse([]).validatedSearchOptions(from: Config())
            Issue.record("expected an empty query to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func validatedOptionsRejectsNonPositivePage() throws {
        do {
            _ = try Sx.parse(["swift", "--page", "0"]).validatedSearchOptions(from: Config())
            Issue.record("expected page 0 to throw")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    // MARK: dry-run reflects tuning

    @Test func dryRunPlanShowsTuning() throws {
        let opts = try Sx.parse([
            "swift", "--site", "github.com", "--time-range", "week", "--page", "2", "-l", "en-US",
        ]).searchOptions(from: Config())
        let plan = Sx.dryRunPlan(engine: nil, config: Config(), options: opts, format: .plain)
        #expect(plan.contains("site:"))
        #expect(plan.contains("github.com"))
        #expect(plan.contains("time-range:"))
        #expect(plan.contains("week"))
        #expect(plan.contains("page:"))
        #expect(plan.contains("language:"))
        #expect(plan.contains("en-US"))
    }
}
