import Foundation

/// Configures which URL paths require authentication.
public struct AuthenticationConfig: Sendable {
    public var inclusions = [String]()
    public var exclusions = [String]()
    public var denied: String?

    public init() {}

    public mutating func include(_ str: String)  { inclusions.append(str) }
    public mutating func include(_ arr: [String]) { inclusions += arr }
    public mutating func exclude(_ str: String)  { exclusions.append(str) }
    public mutating func exclude(_ arr: [String]) { exclusions += arr }
}

/// Pure-string path matching for authentication gating (no HTTP types needed).
public struct AuthFilter: Sendable {
    nonisolated(unsafe) public static var authenticationConfig = AuthenticationConfig()

    /// Checks the global authenticationConfig; pass `config` to use a local config instead.
    public static func shouldWeAccept(_ path: String, using config: AuthenticationConfig? = nil) -> Bool {
        let cfg = config ?? authenticationConfig
        var checkAuth = false
        let wildcardInclusions = cfg.inclusions.filter { $0.contains("*") }
        let wildcardExclusions = cfg.exclusions.filter { $0.contains("*") }

        if cfg.inclusions.contains(path) { checkAuth = true }
        for wInc in wildcardInclusions {
            if wInc == "*" { checkAuth = true }
            else if let prefix = wInc.split(separator: "*").first, path.starts(with: String(prefix)) {
                checkAuth = true
            }
        }
        if cfg.exclusions.contains(path) { checkAuth = false }
        for wInc in wildcardExclusions {
            if let prefix = wInc.split(separator: "*").first, path.starts(with: String(prefix)) {
                checkAuth = false
            }
        }
        return checkAuth
    }
}
