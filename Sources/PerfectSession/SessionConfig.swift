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






	/// CSRF Configuration
	public struct CSRFconfig {

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



	/// CSRF Action to be taken on failure
	public enum CSRFaction {
		case fail, log, none
	}

}
