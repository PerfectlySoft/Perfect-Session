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

import PerfectHTTP
import Foundation

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
		var session = PerfectSession()
		session.token = UUID().uuidString
		session.ipaddress = request.remoteAddress.host
		session.useragent = request.header(.userAgent) ?? "unknown"
		session._state = "new"
		session.setCSRF()
		MemorySessions.sessions[session.token] = session
		return session
	}

	/// Deletes the session for a session identifier.
	public static func destroy(_ request: HTTPRequest, _ response: HTTPResponse) {

		MemorySessions.sessions.removeValue(forKey: (request.session?.token ?? "") )

		// Reset cookie to make absolutely sure it does not get recreated in some circumstances.
		var domain = ""
		if !SessionConfig.cookieDomain.isEmpty {
			domain = SessionConfig.cookieDomain
		}
		response.addCookie(HTTPCookie(
			name: SessionConfig.name,
			value: "",
			domain: domain,
			expires: .relativeSeconds(SessionConfig.idle),
			path: SessionConfig.cookiePath,
			secure: SessionConfig.cookieSecure,
			httpOnly: SessionConfig.cookieHTTPOnly,
			sameSite: SessionConfig.cookieSameSite
			)
		)

	}
	/// Non-static version
	public func destroySession(_ request: HTTPRequest, _ response: HTTPResponse) {
		MemorySessions.destroy(request, response)
	}

	public static func resume(token: String) throws -> PerfectSession {
		var returnSession = PerfectSession()
		if let session = MemorySessions.sessions[token] {
			returnSession = session
		} else {
			throw InvalidSessionError()
		}
		returnSession._state = "resume"
		return returnSession
	}

}
