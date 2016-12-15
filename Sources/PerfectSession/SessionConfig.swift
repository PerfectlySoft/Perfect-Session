//
//  SessionConfig.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

/// Configuration parameters for the session
public struct SessionConfig {
	/// For reference name in a cookie only
	public static var name = "PerfectSession"
	/// Idle time expiry of the session
	public static var idle = 86400
	/// Session Storage Type
	public static var storage: SessionStorage = .memory

	/// Simple switch between memory session and database storage engines
	public enum SessionStorage {
		case memory, database
	}
}
