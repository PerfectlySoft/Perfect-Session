//
//  CORS.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2017-01-13.
//
//

import PerfectHTTP


public class CORSheaders {

	/// Called once before headers are sent to the client. If needed, sets the cookie with the CORS headers.
	public static func make(_ request: HTTPRequest, _ response: HTTPResponse) {
		if SessionConfig.CORS.enabled && SessionConfig.CORS.acceptableHostnames.count > 0 {

			let origin = CSRFSecurity.getOrigin(request)
			if origin.isEmpty {
				// Auto-fail if no origin.
				return
			}
			let wildcards = SessionConfig.CORS.acceptableHostnames.filter({$0.contains("*")})

			var corsOK = false

			// check if specifically in inclusions
			if SessionConfig.CORS.acceptableHostnames.contains(request.path) {
				corsOK = true
			} else {
				// check if covered by a wildcard
				for wInc in wildcards {
					let opts = wInc.split("*")
					if origin.startsWith(opts[0]) { corsOK = true }
					if origin.endsWith(opts.last!) { corsOK = true }
				}
			}
			// ADD CORS HEADERS?
			if corsOK {
				// headers here
				if SessionConfig.CORS.acceptableHostnames.count == 1, SessionConfig.CORS.acceptableHostnames[0] == "*" {
					response.addHeader(.accessControlAllowOrigin, value: "*")
				} else {
					response.addHeader(.accessControlAllowOrigin, value: "\(origin)")
				}

				// Access-Control-Allow-Methods
				let str = SessionConfig.CORS.methods.map{String(describing: $0)}
				response.addHeader(.accessControlAllowMethods, value: str.joined(separator: ", "))

				// Access-Control-Allow-Credentials
				if SessionConfig.CORS.withCredentials {
					response.addHeader(.accessControlAllowCredentials, value: "true")
				}
				// Access-Control-Max-Age
				if SessionConfig.CORS.maxAge > 0 {
					response.addHeader(.accessControlMaxAge, value: String(SessionConfig.CORS.maxAge))
				}
			}

		}
	}

}
