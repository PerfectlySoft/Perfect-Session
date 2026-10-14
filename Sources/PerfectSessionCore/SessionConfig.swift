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
    /// Seconds a session lasts without being saved (each save renews it).
    nonisolated(unsafe) public static var idle           = 86400
    /// Seconds a session lasts from its creation however active it is, or 0 (the default) for no
    /// limit. Checked by `PerfectSession.isExpired()`, `isValid()` and every driver's `resume`.
    nonisolated(unsafe) public static var absoluteTimeout = 0
    nonisolated(unsafe) public static var userAgentLock  = false
    nonisolated(unsafe) public static var IPAddressLock  = false
    @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Exclude your health-check path in AuthenticationConfig.")
    nonisolated(unsafe) public static var healthCheckRoute = "/healthcheck"
    @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Call your driver's clean() on your own schedule.")
    nonisolated(unsafe) public static var purgeInterval  = 3600
    @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it.")
    nonisolated(unsafe) public static var isOAuth2       = false

    nonisolated(unsafe) public static var CSRF = CSRFconfig()
    nonisolated(unsafe) public static var CORS = CORSconfig()

    public struct CSRFconfig: Sendable {
        public init() {}
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Your middleware decides what a failed check does.")
        public var failAction: CSRFaction = .fail
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Check the token with CSRFSecurity.tokenMatches in your middleware.")
        public var checkState             = true
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Check Origin/Host with CSRFSecurity.isValid in your middleware.")
        public var checkHeaders           = true
        /// Origins accepted by `CSRFSecurity.isValid` besides the request's own host.
        public var acceptableHostnames    = [String]()
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Check the token with CSRFSecurity.tokenMatches in your middleware.")
        public var requireToken           = true
    }

    public struct CORSconfig: Sendable {
        public init() {}
        public var enabled             = false
        /// Accept "*" to allow all origins, or list specific hostnames.
        public var acceptableHostnames = [String]()
        /// HTTP method strings, e.g. ["GET", "POST"]
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Send Access-Control-Allow-Methods from your middleware.")
        public var methods: [String]   = ["GET"]
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Send Access-Control-Allow-Headers from your middleware.")
        public var customHeaders       = [String]()
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Send Access-Control-Allow-Credentials from your middleware.")
        public var withCredentials     = false
        @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it. Send Access-Control-Max-Age from your middleware.")
        public var maxAge              = 0
    }

    public enum CSRFaction: Sendable {
        case fail, log, none
    }
}
