import Testing
import SwiftSx
@testable import SxCommand

@Suite struct HistoryCommandParsingTests {

    @Test func historyDefaultLimit() throws {
        let command = try HistoryCommand.parse([])
        #expect(command.limit == 20)
    }

    @Test func historyShortLimitOption() throws {
        let command = try HistoryCommand.parse(["-n", "5"])
        #expect(command.limit == 5)
    }

    @Test func historyLongLimitOption() throws {
        let command = try HistoryCommand.parse(["--limit", "50"])
        #expect(command.limit == 50)
    }

    @Test func historyClearParses() throws {
        // Parsing "history clear" means a HistoryClear subcommand is selected.
        // We can verify by parsing from Sx root.
        _ = try Sx.parse(["history", "clear"])
    }

    @Test func historyCommandName() {
        #expect(HistoryCommand.configuration.commandName == "history")
    }

    @Test func historyClearCommandName() {
        #expect(HistoryClear.configuration.commandName == "clear")
    }

    @Test func sxHasHistorySubcommand() {
        let subcommandNames = Sx.configuration.subcommands.map {
            $0.configuration.commandName
        }
        #expect(subcommandNames.contains("history"))
    }

    @Test func historyNegativeLimitMapsToUsageError() throws {
        // Use --limit=VALUE: "-n -5" is misparsed (ArgumentParser treats -5 as
        // an option). Parsing now succeeds (no validate()); the negative value
        // is rejected at limit-resolution time and mapped to the usage exit
        // code (2) via SxError, so the tool's exit-code contract is honoured.
        let command = try HistoryCommand.parse(["--limit=-5"])
        do {
            _ = try command.resolvedLimit()
            Issue.record("expected resolvedLimit() to throw for a negative limit")
        } catch let error as SxError {
            #expect(error.exitCode == .usage)
        }
    }

    @Test func historyNonNegativeLimitResolves() throws {
        #expect(try HistoryCommand.parse(["--limit=5"]).resolvedLimit() == 5)
    }

    @Test func historyZeroLimitResolves() throws {
        // 0 is valid and means "show all".
        #expect(try HistoryCommand.parse(["--limit=0"]).resolvedLimit() == 0)
    }
}
