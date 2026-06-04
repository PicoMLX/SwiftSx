extension Config {
    /// Returns the path to the `sx` config file.
    ///
    /// Resolution order (XDG Base Directory spec):
    /// 1. If `XDG_CONFIG_HOME` is present and non-empty in `env`, use it as the
    ///    base directory.
    /// 2. Otherwise fall back to `<homeDirectory>/.config`.
    ///
    /// The returned path is always `<base>/sx/config.toml`.
    ///
    /// - Parameters:
    ///   - env: A snapshot of the process environment (or a test double).
    ///   - homeDirectory: The current user's home directory path string.
    /// - Returns: The absolute path to `sx/config.toml` under the config base.
    public static func configFilePath(
        env: [String: String],
        homeDirectory: String
    ) -> String {
        let base: String
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = xdg
        } else {
            base = homeDirectory + "/.config"
        }
        return base + "/sx/config.toml"
    }
}
