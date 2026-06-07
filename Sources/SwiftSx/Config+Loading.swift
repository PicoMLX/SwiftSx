import Foundation
import ShellKit

extension Config {
    /// Loads the SwiftSx configuration from disk, applying normalization and
    /// environment-variable overrides.
    ///
    /// Resolution order:
    /// 1. Compute the config-file path from `XDG_CONFIG_HOME` / home directory.
    /// 2. Gate the URL through the ShellKit sandbox (`Shell.authorize`).
    /// 3. If the file does not exist, return `Config().normalized()` with env
    ///    overrides applied. A missing file is **not** an error here — defaults
    ///    are used (matching upstream `sx`), and the tool fails closed later, at
    ///    search time, if the selected engine turns out not to be configured.
    /// 4. Otherwise decode the TOML, normalize, and apply env overrides.
    ///
    /// - Throws:
    ///   - ``SxError`` with code `.refused` when the sandbox denies access.
    ///   - ``SxError`` with code `.general` when the file exists but can't be read.
    ///   - ``SxError`` with code `.usage` when the TOML is malformed.
    public static func load() async throws -> Config {
        // Read only the keys this layer needs (least-exposure), through the
        // sandbox-mediated environment, rather than snapshotting every variable.
        var env: [String: String] = [:]
        for key in ["XDG_CONFIG_HOME", "BRAVE_API_KEY", "TAVILY_API_KEY", "EXA_API_KEY", "JINA_API_KEY"] {
            if let value = Shell.env(key) { env[key] = value }
        }
        let home = Shell.homeDirectory.path

        let path = Config.configFilePath(env: env, homeDirectory: home)
        let url = Shell.resolve(path)

        do {
            try await Shell.authorize(url)
        } catch {
            // Don't interpolate the raw sandbox error: it can embed the
            // sandbox-resolved absolute path / internal layout. The logical
            // config path is enough to be actionable.
            throw SxError(.refused, "access to the config file at \(path) was refused by the sandbox")
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return Config().normalized().applyingEnvironmentOverrides(env)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SxError(.general, "cannot read config file at \(path): \(error)")
        }
        // Reject invalid UTF-8 rather than silently substituting U+FFFD
        // (which `String(decoding:as:)` does) and then mis-parsing the TOML.
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw SxError(.usage, "config file at \(path) is not valid UTF-8")
        }
        return try Config.decode(fromTOML: text).normalized().applyingEnvironmentOverrides(env)
    }
}
