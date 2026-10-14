import Foundation

/// Pure-string CSRF/CORS header validation. The NIO middleware extracts header
/// values from the request and passes them as strings to these helpers.
public struct CSRFSecurity: Sendable {

    /// True if **origin** (scheme stripped) is in **acceptableHostnames** (by default
    /// `SessionConfig.CSRF.acceptableHostnames`) or equals **host**.
    public static func isValid(origin: String, host: String,
                               acceptableHostnames: [String] = SessionConfig.CSRF.acceptableHostnames) -> Bool {
        let cleanOrigin = stripScheme(origin)
        if cleanOrigin.isEmpty { return false }
        if acceptableHostnames.contains(cleanOrigin) { return true }
        let cleanHost = stripScheme(host)
        if cleanHost.isEmpty { return false }
        return cleanHost == cleanOrigin
    }

    public static func stripScheme(_ str: String) -> String {
        if str.hasPrefix("https://") { return String(str.dropFirst(8)) }
        if str.hasPrefix("http://")  { return String(str.dropFirst(7)) }
        return str
    }
}

/// Validates CORS origin against SessionConfig.CORS.acceptableHostnames.
public struct CORSSecurity: Sendable {

    /// True if **origin** matches an entry in **config**'s `acceptableHostnames` (by default
    /// `SessionConfig.CORS`'s), ignoring
    /// case. `"*"` accepts every origin; in any other entry each `*` matches any run of
    /// characters, and the rest must match in full (`"https://*.example.com"`).
    public static func isAcceptable(origin: String, config: SessionConfig.CORSconfig = SessionConfig.CORS) -> Bool {
        guard config.enabled, !config.acceptableHostnames.isEmpty else {
            return false
        }
        let lower = origin.lowercased()
        for pattern in config.acceptableHostnames {
            if pattern == "*" || matches(lower, pattern: pattern.lowercased()) { return true }
        }
        return false
    }

    /// Glob match where `*` is the only wildcard. Every literal piece must match, in order, with
    /// the first anchored at the start and the last at the end.
    static func matches(_ text: String, pattern: String) -> Bool {
        let pieces = pattern.split(separator: "*", omittingEmptySubsequences: false)
        guard pieces.count > 1 else { return text == pattern }
        var rest = Substring(text)
        guard let first = pieces.first, rest.hasPrefix(first) else { return false }
        rest = rest.dropFirst(first.count)
        guard let last = pieces.last else { return false }
        for piece in pieces.dropFirst().dropLast() where !piece.isEmpty {
            guard let range = rest.range(of: piece) else { return false }
            rest = rest[range.upperBound...]
        }
        return rest.count >= last.count && rest.hasSuffix(last)
    }
}
