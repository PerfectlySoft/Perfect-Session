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
			if let session = MemorySessions.sessions[token] {
				if session.isValid(request) {
					request.session = session
					createSession = false
				} else {
					MemorySessions.destroy(token: token)
				}
			}
		}
		if createSession {
			//start new session
			request.session = MemorySessions.start(request)
		}

		// Now process CSRF
		if request.session._state != "new" {
			if !CSRFFilter.filter(request) {
				switch SessionConfig.CSRFfailAction {
				case .fail:
					callback(.halt(request, response))
					return
				case .log:
					LogFile.info("CSRF FAIL")

				default:
					print("CSRF FAIL (console notification only)")
				}
			}
		}


		// End...
		callback(HTTPRequestFilterResult.continue(request, response))
	}
}

extension SessionMemoryFilter: HTTPResponseFilter {

	/// Called once before headers are sent to the client.
	public func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		MemorySessions.save(session: response.request.session)
		let sessionID = response.request.session.token

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
			if SessionConfig.CSRFCheckState {
				CSRFFilter.setCookie(response)
			}
		}

		callback(.continue)
	}

	/// Called zero or more times for each bit of body data which is sent to the client.
	public func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		callback(.continue)
	}
}
