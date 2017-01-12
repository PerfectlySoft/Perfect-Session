//
//  MemorySession.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

/*	Change History
	====
	0.0.6
		Added to save cookie, ip and user agent
*/

import TurnstileCrypto
import PerfectHTTP

public struct MemorySessions {
	/// Dictionary of sessions
	public static var sessions = [String: PerfectSession]()

	/// Initializes the Session Manager. No config needed!
	private init() {}


	public static func save(session: PerfectSession) {
		var s = session
		s.touch()
		MemorySessions.sessions[session.token] = s
	}

	public static func start(_ request: HTTPRequest) -> PerfectSession {
		let rand = URandom()
		var session = PerfectSession()
		session.token = rand.secureToken
		session.ipaddress = request.remoteAddress.host
		session.useragent = request.header(.userAgent) ?? "unknown"
		session._state = "new"
		session.setCSRF()
		MemorySessions.sessions[session.token] = session
		return session
	}

	/// Deletes the session for a session identifier.
	public static func destroy(token: String) {
		MemorySessions.sessions.removeValue(forKey: token)
	}

	public static func resume(token: String) throws -> PerfectSession {
		var returnSession = PerfectSession()
		if let session = MemorySessions.sessions[token] {
			returnSession = session
		} else {
			throw InvalidSessionError()
		}
		returnSession._state = "resume"
		print("RESUMING?")
		return returnSession
	}

}



