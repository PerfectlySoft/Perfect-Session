import Foundation

/// Pure-string CSRF/CORS header validation. The NIO middleware extracts header
/// values from the request and passes them as strings to these helpers.
public struct CSRFSecurity: Sendable {

    /// True if **origin** (the request's `Origin` header) names the same origin as **host** (its
    /// `Host` header) or as an entry in **acceptableHostnames** (by default
    /// `SessionConfig.CSRF.acceptableHostnames`).
    ///
    /// Comparison ignores case and treats a default port (`:443` for https, `:80` for http) like
    /// no port. When both sides give a scheme, the schemes must match; a side without a scheme
    /// (a `Host` header never has one) takes the other side's. An empty or `null` origin never
    /// matches.
    public static func isValid(origin: String, host: String,
                               acceptableHostnames: [String] = SessionConfig.CSRF.acceptableHostnames) -> Bool {
        let o = Endpoint(origin)
        guard !o.authority.isEmpty, o.authority != "null" || o.scheme != nil else { return false }
        for accepted in acceptableHostnames where Endpoint(accepted).matches(o) { return true }
        let h = Endpoint(host)
        guard !h.authority.isEmpty else { return false }
        return h.matches(o)
    }

    /// An origin or host: an optional scheme and a lowercased host[:port].
    struct Endpoint {
        let scheme: String?
        let authority: String

        init(_ text: String) {
            var rest = Substring(text.lowercased())
            if let range = rest.range(of: "://") {
                scheme = String(rest[..<range.lowerBound])
                rest = rest[range.upperBound...]
            } else {
                scheme = nil
            }
            if rest.hasSuffix("/") { rest = rest.dropLast() }
            authority = String(rest)
        }

        func matches(_ other: Endpoint) -> Bool {
            if let a = scheme, let b = other.scheme, a != b { return false }
            let effective = scheme ?? other.scheme
            return Self.strip(authority, effective) == Self.strip(other.authority, effective)
        }

        static func strip(_ authority: String, _ scheme: String?) -> String {
            let suffix: String
            switch scheme {
            case "https": suffix = ":443"
            case "http":  suffix = ":80"
            default:      return authority
            }
            return authority.hasSuffix(suffix) ? String(authority.dropLast(suffix.count)) : authority
        }
    }

    /// Compares a CSRF token from the request (a header or form field) with the session's
    /// (`session.data["csrf"]`) in time that doesn't depend on where they differ. An empty token
    /// never matches.
    public static func tokenMatches(_ presented: String, _ expected: String) -> Bool {
        let a = Array(presented.utf8), b = Array(expected.utf8)
        guard !b.isEmpty, a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }
        return difference == 0
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
