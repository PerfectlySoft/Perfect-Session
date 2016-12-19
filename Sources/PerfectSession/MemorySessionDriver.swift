//
//  MemorySessionDriver.swift
//  Perfect-Session-Memory-Demo
//
//  Created by Jonathan Guthrie on 2016-12-16.
//
//

import PerfectHTTP
import PerfectSession

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
				if session.isValid() {
					request.session = session
					// print("Session: token \(session.token); created \(session.created); updated \(session.updated)")
					createSession = false
				} else {
					MemorySessions.destroy(token: token)
				}
			}
		}
		if createSession {
			//start new session
			request.session = MemorySessions.start()
			// print("Session (new): token \(request.session.token); created \(request.session.created); updated \(request.session.updated)")

		}

		// print("Performing PerfectSessionMemoryFilter: HTTPRequestFilter (\(request.method))")

		callback(HTTPRequestFilterResult.continue(request, response))
	}
}

extension SessionMemoryFilter: HTTPResponseFilter {

	/// Called once before headers are sent to the client.
	public func filterHeaders(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		MemorySessions.save(session: response.request.session)
		let sessionID = response.request.session.token
		if !sessionID.isEmpty {
			response.addCookie(HTTPCookie(name: SessionConfig.name,
				value: "\(sessionID)",
				domain: nil,
				expires: .relativeSeconds(SessionConfig.idle),
				path: "/",
				secure: nil,
				httpOnly: true)
			)
		}
		// print("Performing PerfectSessionMemoryFilter: HTTPResponseFilter")

		callback(.continue)
	}

	/// Called zero or more times for each bit of body data which is sent to the client.
	public func filterBody(response: HTTPResponse, callback: (HTTPResponseFilterResult) -> ()) {
		callback(.continue)
	}
}
