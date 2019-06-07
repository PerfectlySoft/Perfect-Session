//
//  SessionConfig.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

/*	Change History
====
0.0.6
Added cookieDomain, cookiePath, cookieSecure, cookieHTTPOnly, cookieSameSite
*/

import PerfectHTTP

/// Configuration parameters for the session
public struct SessionConfig {
	/// For reference name in a cookie only
	public static var name = "PerfectSession"

	/// Make cookie domain-specific
	public static var cookieDomain = ""

	/// Make cookie path-specific
	public static var cookiePath = "/"

	/// Make cookie secure
	public static var cookieSecure = false

	/// Make cookie HTTP Only
	public static var cookieHTTPOnly = true

	/// Make cookie sameSite Only
	/// .lax: Cross-site usage is allowed
	/// .strict: The cookie is withheld with any cross-site usage
	public static var cookieSameSite:HTTPCookie.SameSite = .strict



	/// Idle time expiry of the session
	public static var idle = 86400

	/// Session Locked to User Agent
	public static var userAgentLock = false

	/// Session Locked to IP Address
	public static var IPAddressLock = false


	/// CouchDB-Specific option
	public static var couchDatabase = "sessions"
	/// MongoDB-Specific option
	public static var mongoCollection = "sessions"

	/// CSRF Config
	public static var CSRF: CSRFconfig = CSRFconfig()

	/// CORS Config
	public static var CORS: CORSconfig = CORSconfig()

	/// The route used to perform health check. No session is created.
	public static var healthCheckRoute = "/healthcheck"

	/// The interval at which the system should purge stale session entries
	public static var purgeInterval: Int = 3600 // default: once per hour

	/// Specify if we want an OAuth2 behaviour
	public static var isOAuth2 = false

	/// CSRF Configuration
	public struct CSRFconfig {

		public init(){}

		/// Action to take when CSRF validation fails
		public var failAction: CSRFaction = .fail

		/// Global "YES CHECK CSRF" flag
		public var checkState = true

		/// Check referral header
		/// Default: true
		/// Note some of the header checks are not reliable with HTTPS
		public var checkHeaders = true

		/// Array of acceptable hostnames for incoming requets
		public var acceptableHostnames = [String]()

		/// Require Cookie-to-Header Token
		public var requireToken = true

	}

	public struct CORSconfig {

		public init(){}

		/// Enabled: default, false
		public var enabled = false

		/// Array of acceptable hostnames for incoming requets
		/// To enable CORS on all, have a single entry, *
		/// If a match with the origin is found, the origin is echoed back the client in the response
		/// NOTE: If .enabled = true, but this is empty, then CORS will not be generated and therefore will be denied.
		public var acceptableHostnames = [String]()

		/// Array of acceptable methods
		public var methods: [HTTPMethod] = [.get]

		/// An array of custom headers allowed
		public var customHeaders = [String]()

		/// Access-Control-Allow-Credentials true/false.
		/// Standard CORS requests do not send or set any cookies by default.
		/// In order to include cookies as part of the request enable the client to do so by setting to true
		public var withCredentials = false

		/// Max Age (seconds) of request / OPTION caching.
		/// Set to 0 for no caching
		public var maxAge = 0

	}

	/// CSRF Action to be taken on failure
	public enum CSRFaction {
		case fail, log, none
	}
	
}
