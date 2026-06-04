import Testing
import SwiftSx
@testable import SxCommand

@Suite struct SxParsingTests {
    @Test func parsesQueryTerms() throws {
        let command = try Sx.parse(["swift", "concurrency"])
        #expect(command.query == ["swift", "concurrency"])
    }

    @Test func emptyQueryParses() throws {
        let command = try Sx.parse([])
        #expect(command.query.isEmpty)
    }

    @Test func configurationIsWired() {
        #expect(Sx.configuration.commandName == "sx")
        #expect(Sx.configuration.version == SxVersion.current)
    }
}
