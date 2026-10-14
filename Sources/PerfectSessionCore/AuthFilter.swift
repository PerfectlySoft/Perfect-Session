import Foundation

/// Configures which URL paths require authentication. See `AuthFilter.requiresAuthentication`.
public struct AuthenticationConfig: Sendable {
    /// Paths that require authentication. `"/admin"` covers `/admin` and everything below it
    /// (not `/administrator`); `"/admin/*"` means the same; `"*"` covers every path.
    public var inclusions = [String]()
    /// Paths that don't, overriding `inclusions`, with the same matching.
    public var exclusions = [String]()
    @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Redirect or respond in your middleware.")
    public var denied: String?
    /// Compare paths ignoring ASCII case (the default), for servers whose routing ignores
    /// case, as Perfect-NIO 0.1's does.
    public var caseInsensitive = true

    public init() {}

    public mutating func include(_ str: String)  { inclusions.append(str) }
    public mutating func include(_ arr: [String]) { inclusions += arr }
    public mutating func exclude(_ str: String)  { exclusions.append(str) }
    public mutating func exclude(_ arr: [String]) { exclusions += arr }
}

/// Path matching for authentication gating (no HTTP types needed).
public struct AuthFilter: Sendable {
    nonisolated(unsafe) public static var authenticationConfig = AuthenticationConfig()

    /// Whether **path** requires authentication under **config** (by default
    /// `authenticationConfig`). Pass the request's path without its query string.
    ///
    /// The path is split on `/`, empty and `.` segments are dropped, and segments are compared
    /// ignoring case unless `caseInsensitive` is off. A pattern matches its own path and every
    /// path below it. `*` is a wildcard only as a pattern's whole final segment; an inclusion
    /// that uses `*` any other way (`"*.json"`, `"/admin*"`) makes every path require
    /// authentication, and such an exclusion matches nothing.
    ///
    /// When any inclusion is configured, a path containing a `..` segment, `%`, `;` or `\`
    /// requires authentication whatever the patterns say: different servers decode and
    /// normalize those differently, so the path can't be matched reliably.
    public static func requiresAuthentication(_ path: String, using config: AuthenticationConfig? = nil) -> Bool {
        let cfg = config ?? authenticationConfig
        guard !cfg.inclusions.isEmpty else { return false }
        if path.contains(where: { $0 == "%" || $0 == ";" || $0 == "\\" }) { return true }
        guard let segments = normalize(path, caseInsensitive: cfg.caseInsensitive) else { return true }
        var required = false
        for pattern in cfg.inclusions {
            switch match(segments, pattern: pattern, caseInsensitive: cfg.caseInsensitive) {
            case .matches, .invalid: required = true
            case .noMatch: break
            }
            if required { break }
        }
        guard required else { return false }
        for pattern in cfg.exclusions
            where match(segments, pattern: pattern, caseInsensitive: cfg.caseInsensitive) == .matches {
            return false
        }
        return true
    }

    /// True when **path** requires authentication: the same as `requiresAuthentication`.
    @available(*, deprecated, renamed: "requiresAuthentication(_:using:)",
               message: "Returns true when authentication is REQUIRED; use requiresAuthentication(_:using:).")
    public static func shouldWeAccept(_ path: String, using config: AuthenticationConfig? = nil) -> Bool {
        requiresAuthentication(path, using: config)
    }

    enum Match { case matches, noMatch, invalid }

    /// Path segments without empty and `.` ones, or nil if there's a `..` segment.
    static func normalize(_ path: String, caseInsensitive: Bool) -> [Substring]? {
        let text = caseInsensitive ? path.lowercased() : path
        var segments: [Substring] = []
        for segment in text.split(separator: "/", omittingEmptySubsequences: true) where segment != "." {
            if segment == ".." { return nil }
            segments.append(segment)
        }
        return segments
    }

    static func match(_ segments: [Substring], pattern: String, caseInsensitive: Bool) -> Match {
        guard var parts = normalize(pattern, caseInsensitive: caseInsensitive) else { return .invalid }
        if parts.last == "*" { parts.removeLast() }
        guard !parts.contains(where: { $0.contains("*") }) else { return .invalid }
        guard segments.count >= parts.count else { return .noMatch }
        return zip(segments, parts).allSatisfy { $0 == $1 } ? .matches : .noMatch
    }
}
