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
import Dispatch

public struct MemorySessions {
	/// Dictionary of sessions
	private static var syncSessions = [String: PerfectSession]()
	private static let syncQueue = DispatchQueue(label: "MemorySessions")

	public static func get(key: String) -> PerfectSession? {
		return syncQueue.sync {
			return syncSessions[key]
		}
	}
	
	public static func set(key: String, _ session: PerfectSession) {
		syncQueue.sync {
			syncSessions[key] = session
		}
	}
	
	public static func remove(key: String) {
		syncQueue.sync {
			_ = syncSessions.removeValue(forKey: key)
		}
	}
	
	/// Initializes the Session Manager. No config needed.
	private init() {}


	public static func save(session: PerfectSession) {
		var s = session
		s.touch()
		MemorySessions.set(key: session.token, s)
	}

	public static func start(_ request: HTTPRequest) -> PerfectSession {
		var session = PerfectSession()
		session.token = UUID().uuidString

		// adding for x-forwarded-for support:
		let ff = request.header(.xForwardedFor) ?? ""
		if ff.isEmpty {
			// session setting normally (not load balanced)
			session.ipaddress = request.remoteAddress.host
		} else {
			// Session is coming through a load balancer or proxy
			session.ipaddress = ff
		}
		session.useragent = request.header(.userAgent) ?? "unknown"
		session._state = "new"
		session.setCSRF()
		MemorySessions.set(key: session.token, session)
		return session
	}

	/// Deletes the session for a session identifier.
	public static func destroy(_ request: HTTPRequest, _ response: HTTPResponse) {
		if let token = request.session?.token {
			MemorySessions.remove(key: token)
		}

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
		if let session = MemorySessions.get(key: token) {
			returnSession = session
		} else {
			throw InvalidSessionError()
		}
		returnSession._state = "resume"
		return returnSession
	}

}
