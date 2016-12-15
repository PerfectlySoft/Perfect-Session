//
//  MemorySession.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

public class MemorySessionManager: PerfectSessionManager {
	/// Dictionary of sessions
	private var sessions = [String: PerfectSession]()

	/// Initializes the Session Manager. No config needed!
	public init() {}


	public func save(session: PerfectSession) {
		sessions[session.token] = session
	}

	/// Deletes the session for a session identifier.
	public func destroy(token: String) {
		sessions.removeValue(forKey: token)
	}

	public func resume(token: String) throws -> PerfectSession {
		if let session = sessions[token] {
			return session
		} else {
			throw InvalidSessionError()
		}
	}
}
