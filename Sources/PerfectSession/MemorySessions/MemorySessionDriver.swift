//
//  MemorySessionDriver.swift
//  Perfect-Session-Memory-Demo
//
//  Created by Jonathan Guthrie on 2016-12-16.
//
//

/*	Change History
====
0.0.6
Added to response add cookie: cookieDomain, cookiePath, cookieSecure, cookieHTTPOnly, cookieSameSite
0.0.7
Added CSRF support
*/

import PerfectHTTP
import PerfectLogger

public struct SessionMemoryDriver {
	public var requestFilter: (HTTPRequestFilter, HTTPFilterPriority)
	public var responseFilter: (HTTPResponseFilter, HTTPFilterPriority)


	public init() {
		let filter = SessionMemoryFilter()
		requestFilter = (filter, HTTPFilterPriority.high)
		responseFilter = (filter, HTTPFilterPriority.high)
	}
}
public class SessionMemoryFilter {
	public init() {}
}

extension SessionMemoryFilter: HTTPRequestFilter {

	public func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {

		var createSession = true
		if let token = request.getCookie(name: SessionConfig.name) {
			if var session = MemorySessions.sessions[token] {
				if session.isValid(request) {
					session._state = "resume"
					request.session = session
					createSession = false
				} else {
					MemorySessions.destroy(request, response)
				}
			}
		} else if let s = request.param(name: "session"), !s.isEmpty {
			if var session = MemorySessions.sessions[s] {
				if session.isValid(request) {
					session._state = "resume"
					request.session = session
					createSession = false
				} else {
					MemorySessions.destroy(request, response)
				}
			}

		}
		if createSession {
			//start new session
			request.session = MemorySessions.start(request)
		}

		// Now process CSRF
		if request.session?._state != "new" || request.method == .post {
			//print("Check CSRF Request: \(CSRFFilter.filter(request))")
			if !CSRFFilter.filter(request) {

				switch SessionConfig.CSRF.failAction {
				case .fail:
					response.status = .notAcceptable
					callback(.halt(request, response))
					return
				case .log:
					LogFile.info("CSRF FAIL")

				default:
					print("CSRF FAIL (console notification only)")
				}
			}
		}

		CORSheaders.make(request, response)
		// End. Continue
		callback(HTTPRequestFilterResult.continue(request, response))
	}

	/// Wrapper enabling PerfectHTTP 2.1 filter support
	public static func filterAPIRequest(data: [String:Any]) throws -> HTTPRequestFilter {
		return SessionMemoryFilter()
	}

}

extension SessionMemoryFilter: HTTPResponseFilter {

	/// Called once before headers are sent to the client.
	public func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		guard let session = response.request.session else {
			return callback(.continue)
		}
		let sessionID = session.token
		if !session.token.isEmpty {
			MemorySessions.save(session: session)
		}
		// 0.0.6 updates
		var domain = ""
		if !SessionConfig.cookieDomain.isEmpty {
			domain = SessionConfig.cookieDomain
		}

		if !sessionID.isEmpty {
			response.addCookie(HTTPCookie(
				name: SessionConfig.name,
				value: "\(sessionID)",
				domain: domain,
				expires: .relativeSeconds(SessionConfig.idle),
				path: SessionConfig.cookiePath,
				secure: SessionConfig.cookieSecure,
				httpOnly: SessionConfig.cookieHTTPOnly,
				sameSite: SessionConfig.cookieSameSite
				)
			)

			// CSRF Set Cookie
			if SessionConfig.CSRF.checkState {
				CSRFFilter.setCookie(response)
			}
		}
		callback(.continue)
	}

	/// Called zero or more times for each bit of body data which is sent to the client.
	public func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		callback(.continue)
	}

	/// Wrapper enabling PerfectHTTP 2.1 filter support
	public static func filterAPIResponse(data: [String:Any]) throws -> HTTPResponseFilter {
		return SessionMemoryFilter()
	}
	
}
