import Foundation

/// Pure-string CSRF/CORS header validation. The NIO middleware extracts header
/// values from the request and passes them as strings to these helpers.
public struct CSRFSecurity: Sendable {

    public static func isValid(origin: String, host: String) -> Bool {
        let cleanOrigin = stripScheme(origin)
        if cleanOrigin.isEmpty { return false }
        if !SessionConfig.CSRF.acceptableHostnames.isEmpty {
            for check in SessionConfig.CSRF.acceptableHostnames {
                if check == cleanOrigin { return true }
            }
        }
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

    /// True if **origin** matches an entry in `SessionConfig.CORS.acceptableHostnames`, ignoring
    /// case. `"*"` accepts every origin; in any other entry each `*` matches any run of
    /// characters, and the rest must match in full (`"https://*.example.com"`).
    public static func isAcceptable(origin: String) -> Bool {
        guard SessionConfig.CORS.enabled, !SessionConfig.CORS.acceptableHostnames.isEmpty else {
            return false
        }
        let lower = origin.lowercased()
        for pattern in SessionConfig.CORS.acceptableHostnames {
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
