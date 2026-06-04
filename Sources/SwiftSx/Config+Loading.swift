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
    ///    overrides applied (missing config is **not** an error — defaults are used,
    ///    matching upstream `sx` behaviour).
    /// 4. Otherwise decode the TOML, normalize, and apply env overrides.
    ///
    /// - Throws:
    ///   - ``SxError`` with exit code `.refused` when the sandbox denies access.
    ///   - ``SxError`` with exit code `.usage` when the TOML is malformed.
    public static func load() async throws -> Config {
        let env = Shell.current.environment.variables
        let home = Shell.homeDirectory.path

        let path = Config.configFilePath(env: env, homeDirectory: home)
        let url = Shell.resolve(path)

        do {
            try await Shell.authorize(url)
        } catch {
            throw SxError(.refused, "cannot access config file at \(path): \(error)")
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return Config().normalized().applyingEnvironmentOverrides(env)
        }

        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        return try Config.decode(fromTOML: text).normalized().applyingEnvironmentOverrides(env)
    }
}
