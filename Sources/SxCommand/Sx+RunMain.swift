import ArgumentParser
import Foundation
import ShellKit
import SwiftSx

extension Sx {

    /// What the process should do in response to an error that reached the top
    /// level (either from argument parsing or from a command's `run()`).
    ///
    /// Factored out of ``runAsMain()`` so the mapping is unit-testable without
    /// actually terminating the process.
    enum RootErrorAction: Equatable {
        /// A "clean" exit (`--help` / `--version`): let ArgumentParser print to
        /// stdout and exit `0`.
        case cleanExit
        /// A command already emitted its own `sx:` diagnostic and converted the
        /// failure to an exit code — terminate with that code, no extra output.
        case silentExit(Int32)
        /// Emit `message` (already `sx:`-prefixed) on stderr, then exit `code`.
        case diagnostic(String, Int32)
    }

    /// Maps any top-level error to the action the process should take.
    ///
    /// The point of this layer is that **every** failure surfaced to an agent —
    /// including ArgumentParser's own parse/validation failures (unknown flag,
    /// a non-integer `--limit=abc`, a missing option value, an unknown
    /// subcommand) — is reported with an `sx:`-prefixed diagnostic and one of
    /// the tool's stable exit codes, never ArgumentParser's default usage code.
    ///
    /// Resolution order:
    /// 1. ``SxError`` → its message + stable code.
    /// 2. A "clean" exit (`--help` / `--version`) → ``RootErrorAction/cleanExit``.
    /// 3. An ``ExitCode`` thrown by a command (which already printed its `sx:`
    ///    diagnostic) → ``RootErrorAction/silentExit(_:)`` with that code.
    /// 4. Anything else → a `sx:`-prefixed diagnostic. ArgumentParser
    ///    parse/validation failures map to the usage code (`2`); any other
    ///    stray error maps to the general code (`1`).
    static func rootErrorAction(for error: any Error) -> RootErrorAction {
        if let sxError = error as? SxError {
            return .diagnostic("sx: \(sxError.message)", sxError.exitCode.rawValue)
        }

        if exitCode(for: error) == .success {
            return .cleanExit
        }

        if let exit = error as? ExitCode {
            return .silentExit(exit.rawValue)
        }

        let mapped: Int32 = exitCode(for: error) == .validationFailure
            ? SxExitCode.usage.rawValue
            : SxExitCode.general.rawValue
        return .diagnostic("sx: \(message(for: error))", mapped)
    }

    /// The process entry point: parse, run, and terminate with a stable exit
    /// code, routing every error through ``rootErrorAction(for:)``.
    ///
    /// The thin executable target calls this so all exit-code / diagnostic
    /// policy lives here (and is exercised by the SDK tests) rather than in the
    /// `@main` wrapper.
    public static func runAsMain() async -> Never {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            switch rootErrorAction(for: error) {
            case .cleanExit:
                // ArgumentParser prints the help/version text to stdout, exit 0.
                Sx.exit(withError: error)
            case .silentExit(let code):
                Foundation.exit(code)
            case .diagnostic(let message, let code):
                Shell.current.stderr.write(Data((message + "\n").utf8))
                Foundation.exit(code)
            }
        }
        Foundation.exit(SxExitCode.success.rawValue)
    }
}
