//
//  CSRFFilter.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2017-01-10.
//
//

import PerfectHTTP

public class CSRFFilter {
	public init() {}

	public static func filter(_ request: HTTPRequest) -> Bool {
		guard let session = request.session else {
			return false
		}
		// Declare and use csrfToken from within Session
		var csrfTokenSession = ""
		if let t = session.data["csrf"] {
			csrfTokenSession = t as! String
		}

		if session._state == "new" && request.method == .post {
			print("CSRF WARNING: NEW SESSION AND POST")
			return false
		}

		// If new session, not really a proper check so return true
		if session._state != "new" {
			// check headers and if post method, if there's a token (if POST method)
			if request.method == .post && SessionConfig.CSRF.checkHeaders {
				if !CSRFSecurity.checkHeaders(request) {
					print("CSRF WARNING: CSRFSecurity.checkHeaders FAIL AND POST")
					return false
				}
			}
			if SessionConfig.CSRF.requireToken {
				var csrfTokenIncoming = ""
				var isCSRFHeaderToken = false
//				print("params in CSRFFilter.filter \(request.params())")
				if let t = request.param(name: "_csrf"), !t.isEmpty {
					csrfTokenIncoming = t
				} else if request.header(.contentType) == "application/json" {
					// get from header, might be a JSON request
					isCSRFHeaderToken = true
					if let t = request.header(.xCsrfToken) {
						csrfTokenIncoming = t
					}
				}
//				print("csrfTokenSession: \(csrfTokenSession)")
//				print("csrfTokenIncoming: \(csrfTokenIncoming)")
//				print("request.header(.xCsrfToken): \(request.header(.xCsrfToken))")
//				print("request.header(.contentType): \(request.header(.contentType))")


				// Double make sure of POST requests
				if request.method == .post || isCSRFHeaderToken {
					if csrfTokenSession != csrfTokenIncoming {
						return false
					}
				}
			}
		}
		return true
	}

	/// Called once before headers are sent to the client. If needed, sets the cookie with the CSRF token.
	public static func setCookie(_ response: HTTPResponse) {
		guard let session = response.request.session else {
			return
		}
		var domain = ""
		if !SessionConfig.cookieDomain.isEmpty {
			domain = SessionConfig.cookieDomain
		}
		if let t = session.data["csrf"] {
			response.addCookie(HTTPCookie(
				name: "CSRF-TOKEN",
				value: "\(t)",
				domain: domain,
				expires: .relativeSeconds(SessionConfig.idle),
				path: SessionConfig.cookiePath,
				secure: SessionConfig.cookieSecure,
				httpOnly: SessionConfig.cookieHTTPOnly,
				sameSite: SessionConfig.cookieSameSite
			))
		}
	}

}




