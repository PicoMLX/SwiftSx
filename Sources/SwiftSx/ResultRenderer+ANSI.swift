/// ANSI colour helpers used by ``ResultRenderer/renderPlain(query:results:expand:noColor:)``.
///
/// All escape sequences are gated behind the `enabled` flag so that
/// `noColor: true` (or `NO_COLOR` / non-TTY) produces plain text that
/// agents can parse reliably.
extension ResultRenderer {

    /// The set of ANSI styles used by the plain renderer.
    enum ANSIStyle: Sendable {
        case cyan
        case greenBold
        case yellow
        case whiteBold
        case dim
        case reset
    }

    /// Wrap `text` in the ANSI escape codes for `style` when `enabled` is
    /// `true`; return `text` unchanged otherwise.
    static func color(_ text: String, _ style: ANSIStyle, enabled: Bool) -> String {
        guard enabled else { return text }
        let (open, close) = ansiCodes(style)
        return "\(open)\(text)\(close)"
    }

    // MARK: - Private

    private static func ansiCodes(_ style: ANSIStyle) -> (String, String) {
        let reset = "\u{001B}[0m"
        switch style {
        case .cyan:      return ("\u{001B}[36m",   reset)
        case .greenBold: return ("\u{001B}[1;32m", reset)
        case .yellow:    return ("\u{001B}[33m",   reset)
        case .whiteBold: return ("\u{001B}[1;37m", reset)
        case .dim:       return ("\u{001B}[2m",    reset)
        case .reset:     return ("",               reset)
        }
    }
}
