import Testing
@testable import SxCommand

@Suite struct OutputFlagTests {

    @Test func parsesShortOutputFlag() throws {
        #expect(try Sx.parse(["q", "-o", "results.json"]).output == "results.json")
    }

    @Test func parsesLongOutputFlag() throws {
        #expect(try Sx.parse(["q", "--output", "out.txt"]).output == "out.txt")
    }

    @Test func outputDefaultsToNil() throws {
        #expect(try Sx.parse(["q"]).output == nil)
    }

    @Test func outputCombinesWithOtherFlags() throws {
        let cmd = try Sx.parse(["swift", "--json", "-o", "r.json", "-n", "5"])
        #expect(cmd.output == "r.json")
        #expect(cmd.json)
        #expect(cmd.count == 5)
        #expect(cmd.query == ["swift"])
    }
}
