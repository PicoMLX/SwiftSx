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
}
