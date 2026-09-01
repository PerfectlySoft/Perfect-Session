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

    public static func isAcceptable(origin: String) -> Bool {
        guard SessionConfig.CORS.enabled, !SessionConfig.CORS.acceptableHostnames.isEmpty else {
            return false
        }
        let lower = origin.lowercased()
        if SessionConfig.CORS.acceptableHostnames.contains("*") { return true }
        if SessionConfig.CORS.acceptableHostnames.contains(lower) { return true }
        for pattern in SessionConfig.CORS.acceptableHostnames where pattern.contains("*") && pattern != "*" {
            let parts = pattern.split(separator: "*")
            if let first = parts.first, lower.starts(with: String(first)) { return true }
            if let last  = parts.last,  lower.hasSuffix(String(last))      { return true }
        }
        return false
    }
}
