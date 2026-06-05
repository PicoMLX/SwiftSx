import ArgumentParser
import Testing
import SwiftSx
@testable import SxCommand

@Suite struct RootErrorMappingTests {

    // MARK: SxError → prefixed diagnostic with its stable code

    @Test func sxErrorMapsToPrefixedDiagnostic() {
        let action = Sx.rootErrorAction(for: SxError(.refused, "blocked by sandbox"))
        #expect(action == .diagnostic("sx: blocked by sandbox", 3))
    }

    @Test func sxErrorPreservesUsageCode() {
        let action = Sx.rootErrorAction(for: SxError(.usage, "bad input"))
        #expect(action == .diagnostic("sx: bad input", 2))
    }

    // MARK: ExitCode passes through silently (command already printed sx:)

    @Test func exitCodePassesThroughSilently() {
        #expect(Sx.rootErrorAction(for: ExitCode(7)) == .silentExit(7))
        #expect(Sx.rootErrorAction(for: ExitCode(SxExitCode.general.rawValue)) == .silentExit(1))
    }

    // MARK: --help / --version are clean exits (stdout, exit 0)

    @Test func helpRequestParsesWithoutThrowing() throws {
        // Unlike --version (which throws a clean exit at parse time), ArgumentParser
        // returns an internal help command for --help; that command's run() then
        // throws the clean exit, which runAsMain routes the same way (verified via
        // the --version case below). Here we only confirm the parse step itself
        // does not throw, so runAsMain reaches and runs that help command.
        _ = try Sx.parseAsRoot(["--help"])
    }

    @Test func versionRequestIsCleanExit() throws {
        do {
            _ = try Sx.parseAsRoot(["--version"])
            Issue.record("expected --version to throw a clean exit")
        } catch {
            #expect(Sx.rootErrorAction(for: error) == .cleanExit)
        }
    }

    // MARK: ArgumentParser parse/validation failures → usage code (2) + sx: prefix

    @Test func unknownFlagMapsToUsageDiagnostic() throws {
        do {
            _ = try Sx.parseAsRoot(["--definitely-not-a-flag"])
            Issue.record("expected an unknown flag to throw a parse error")
        } catch {
            guard case let .diagnostic(message, code) = Sx.rootErrorAction(for: error) else {
                Issue.record("expected a diagnostic action")
                return
            }
            #expect(code == 2)
            #expect(message.hasPrefix("sx: "))
        }
    }

    @Test func nonIntegerLimitMapsToUsage() throws {
        // `sx history --limit=abc` fails ArgumentParser's Int conversion before
        // run() — it must still surface as the usage exit code (2). This is the
        // exact case the reviewer flagged on the history PR.
        do {
            _ = try Sx.parseAsRoot(["history", "--limit=abc"])
            Issue.record("expected --limit=abc to throw a parse error")
        } catch {
            guard case let .diagnostic(message, code) = Sx.rootErrorAction(for: error) else {
                Issue.record("expected a diagnostic action")
                return
            }
            #expect(code == 2)
            #expect(message.hasPrefix("sx: "))
        }
    }
}
