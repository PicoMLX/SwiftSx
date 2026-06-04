import Testing
@testable import SwiftSx

@Suite struct SxExitCodeTests {
    @Test func exitCodesAreStable() {
        // These values are part of the tool's contract with agents.
        #expect(SxExitCode.success.rawValue == 0)
        #expect(SxExitCode.general.rawValue == 1)
        #expect(SxExitCode.usage.rawValue == 2)
        #expect(SxExitCode.refused.rawValue == 3)
        #expect(SxExitCode.empty.rawValue == 4)
        #expect(SxExitCode.auth.rawValue == 7)
    }
}

@Suite struct SxErrorTests {
    @Test func carriesCodeAndMessage() {
        let error = SxError(.usage, "--num must be between 1 and 100")
        #expect(error.exitCode == .usage)
        #expect(error.message == "--num must be between 1 and 100")
        #expect(error.description == "sx: --num must be between 1 and 100")
    }
}
