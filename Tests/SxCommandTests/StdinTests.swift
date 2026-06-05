import Testing
import SwiftSx
@testable import SxCommand

@Suite struct StdinTests {

    @Test func loneDashTriggersStdin() throws {
        #expect(try Sx.parse(["-"]).readsQueryFromStdin)
    }

    @Test func normalQueryDoesNotTriggerStdin() throws {
        #expect(!(try Sx.parse(["swift"]).readsQueryFromStdin))
        #expect(!(try Sx.parse([]).readsQueryFromStdin))
        // Only a *lone* "-" is the stdin sentinel.
        #expect(!(try Sx.parse(["foo", "-"]).readsQueryFromStdin))
    }

    @Test func queryOverrideReplacesPositionalQuery() throws {
        let opts = try Sx.parse(["-"]).searchOptions(from: Config(), queryOverride: "piped query")
        #expect(opts.query == "piped query")
    }

    @Test func queryOverrideIsTrimmed() throws {
        let opts = try Sx.parse(["-"]).searchOptions(from: Config(), queryOverride: "  spaced query  \n")
        #expect(opts.query == "spaced query")
    }

    @Test func emptyStdinOverrideFailsValidation() throws {
        do {
            _ = try Sx.parse(["-"]).validatedSearchOptions(from: Config(), queryOverride: "   \n")
            Issue.record("expected an empty stdin query to fail validation")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func nilOverrideUsesPositionalQuery() throws {
        // Backward-compatible: with no override, the positional query is used.
        let opts = try Sx.parse(["swift", "concurrency"]).searchOptions(from: Config())
        #expect(opts.query == "swift concurrency")
    }
}
