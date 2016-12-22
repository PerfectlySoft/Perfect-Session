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
	/// Session Storage Type
	public static var storage: SessionStorage = .memory

	/// Session Locked to User Agent
	public static var userAgentLock = false

	/// Session Locked to IP Address
	public static var IPAddressLock = false


	/// CouchDB-Specific option
	public static var couchDatabase = "sessions"
	/// MongoDB-Specific option
	public static var mongoCollection = "sessions"
	
	
	
	/// Simple switch between memory session and database storage engines
	public enum SessionStorage {
		case memory, database
	}
}
