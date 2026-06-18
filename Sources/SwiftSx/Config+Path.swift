import Foundation

extension Config {
    /// Returns the path to the `sx` config file.
    ///
    /// Resolution order (XDG Base Directory spec):
    /// 1. If `XDG_CONFIG_HOME` is present and non-empty in `env`, use it as the
    ///    base directory.
    /// 2. Otherwise fall back to `<homeDirectory>/.config`.
    ///
    /// The returned path is always `<base>/sx/config.toml`. Path components are
    /// joined via `URL` APIs so a trailing slash on the base can't produce a
    /// malformed path.
    ///
    /// - Parameters:
    ///   - env: The relevant environment variables (at least `XDG_CONFIG_HOME`).
    ///   - homeDirectory: The current user's home directory path string.
    /// - Returns: The absolute path to `sx/config.toml` under the config base.
    public static func configFilePath(
        env: [String: String],
        homeDirectory: String
    ) -> String {
        let base: URL
        // The XDG spec requires XDG_CONFIG_HOME to be an absolute path; a
        // relative value is invalid and must be ignored (a relative path would
        // otherwise resolve against the process's current directory). The
        // leading-"/" test is deliberate: it also rejects tilde forms (~/...),
        // which NSString.isAbsolutePath would accept but URL(fileURLWithPath:)
        // does not expand. (SwiftSx targets macOS/Linux only.)
        if let xdg = env["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".config")
        }
        return base
            .appendingPathComponent("sx")
            .appendingPathComponent("config.toml")
            .path
    }
}
