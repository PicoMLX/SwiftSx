import TOMLDecoder

extension Config {
    /// Decode a ``Config`` from a TOML string.
    ///
    /// - Parameter toml: The raw TOML text (e.g. the contents of `config.toml`).
    /// - Returns: A fully-populated ``Config`` with missing keys filled with defaults.
    /// - Throws: ``SxError`` with exit code `.usage` when the TOML is invalid.
    public static func decode(fromTOML toml: String) throws -> Config {
        do {
            return try TOMLDecoder().decode(Config.self, from: toml)
        } catch {
            throw SxError(.usage, "config is not valid TOML: \(error)")
        }
    }
}
