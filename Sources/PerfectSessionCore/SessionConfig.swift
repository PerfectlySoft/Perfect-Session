import Foundation

public enum CookieSameSite: String, Sendable {
    case strict = "Strict"
    case lax    = "Lax"
    case none   = "None"
}

public struct SessionConfig {
    nonisolated(unsafe) public static var name           = "PerfectSession"
    nonisolated(unsafe) public static var cookieDomain   = ""
    nonisolated(unsafe) public static var cookiePath     = "/"
    nonisolated(unsafe) public static var cookieSecure   = false
    nonisolated(unsafe) public static var cookieHTTPOnly = true
    nonisolated(unsafe) public static var cookieSameSite: CookieSameSite = .strict
    nonisolated(unsafe) public static var idle           = 86400
    nonisolated(unsafe) public static var userAgentLock  = false
    nonisolated(unsafe) public static var IPAddressLock  = false
    nonisolated(unsafe) public static var healthCheckRoute = "/healthcheck"
    nonisolated(unsafe) public static var purgeInterval  = 3600
    nonisolated(unsafe) public static var isOAuth2       = false

    nonisolated(unsafe) public static var CSRF = CSRFconfig()
    nonisolated(unsafe) public static var CORS = CORSconfig()

    public struct CSRFconfig: Sendable {
        public init() {}
        public var failAction: CSRFaction = .fail
        public var checkState             = true
        public var checkHeaders           = true
        public var acceptableHostnames    = [String]()
        public var requireToken           = true
    }

    public struct CORSconfig: Sendable {
        public init() {}
        public var enabled             = false
        /// Accept "*" to allow all origins, or list specific hostnames.
        public var acceptableHostnames = [String]()
        /// HTTP method strings, e.g. ["GET", "POST"]
        public var methods: [String]   = ["GET"]
        public var customHeaders       = [String]()
        public var withCredentials     = false
        public var maxAge              = 0
    }

    public enum CSRFaction: Sendable {
        case fail, log, none
    }
}
