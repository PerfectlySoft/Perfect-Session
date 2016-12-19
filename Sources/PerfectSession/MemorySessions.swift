//
//  MemorySession.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

import TurnstileCrypto

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

	public static func start() -> PerfectSession {
		let rand = URandom()
		var session = PerfectSession()
		session.token = rand.secureToken
		MemorySessions.sessions[session.token] = session
		return session
	}

	/// Deletes the session for a session identifier.
	public static func destroy(token: String) {
		MemorySessions.sessions.removeValue(forKey: token)
	}

	public static func resume(token: String) throws -> PerfectSession {
		if let session = MemorySessions.sessions[token] {
			return session
		} else {
			throw InvalidSessionError()
		}
	}

}



