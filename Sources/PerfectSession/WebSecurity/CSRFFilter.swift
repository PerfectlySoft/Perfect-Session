//
//  CSRFFilter.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2017-01-10.
//
//

import PerfectHTTP
import TurnstileCrypto

public class CSRFFilter {
	public init() {}

	public static func filter(_ request: HTTPRequest) -> Bool {
		let rand = URandom()

		// Declare and use csrfToken from within Session
		var csrfTokenSession = ""
		if SessionConfig.CSRFrequireToken {
			if let t = request.session.data["csrf"] { csrfTokenSession = t as! String }

			// if no CSRF token then put one in the session
			if csrfTokenSession.isEmpty {
				request.session.data["csrf"] = rand.secureToken
			}
		}

		if request.session._state == "new" && request.method == .post {
			return false
		}

		// If new session, not really a proper check so return true
		if request.session._state != "new" {
			// check headers and if post method, if there's a token (if POST method)
			if request.method == .post && SessionConfig.CSRFcheckHeaders {
				if !CSRFSecurity.checkHeaders(request) {
					return false
				}
			}
			if SessionConfig.CSRFrequireToken {
				var csrfTokenIncoming = ""
				var isCSRFHeaderToken = false
				if let t = request.param(name: "_csrf") {
					csrfTokenIncoming = t
				} else if request.header(.contentType) == "application/json" {
					// get from header, might be a JSON request
					isCSRFHeaderToken = true
					if let t = request.header(.xCsrfToken) {
						csrfTokenIncoming = t
					}
				}


				// Double make sure of POST requests
				if request.method == .post || isCSRFHeaderToken {
					if csrfTokenSession != csrfTokenIncoming {
						return false
					}
				}
				// Now make sure there is a header X-Requested-By or similar
				// http://security.stackexchange.com/questions/23371/csrf-protection-with-custom-headers-and-without-validating-token
				/*
				"X-Requested-By" recognized by Jersey/others
				"X-Requested-With" set by jQuery
				"X-XSRF-TOKEN" set by Angular (unsupported?)
				"X-CSRF-TOKEN" recognized by the Play framework
				*/
				if (request.header(.xRequestedBy)?.isEmpty)! && (request.header(.xRequestedWith)?.isEmpty)! && (request.header(.xCsrfToken)?.isEmpty)! {
					return false
				}

				// Now make sure there is a custom header with the CSRF token

			}
		}
		return true
	}

	/// Called once before headers are sent to the client. If needed, sets the cookie with the session id.
	public static func setCookie(_ response: HTTPResponse) {
		var domain = ""
		if !SessionConfig.cookieDomain.isEmpty {
			domain = SessionConfig.cookieDomain
		}
		if let t = response.request.session.data["csrf"] {
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




