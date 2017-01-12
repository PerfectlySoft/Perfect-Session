//
//  CSRF.swift
//  PerfectWebSecurity
//
//  Created by Jonathan Guthrie on 2017-01-02.
//	Copyright (C) 2017 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2017 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

/*

https://www.owasp.org/index.php/Cross-Site_Request_Forgery_(CSRF)
https://www.owasp.org/index.php/CSRF_Prevention_Cheat_Sheet

- check referral header - only works for http
- Cookie-to-Header Token
Set-Cookie: Csrf-token=i8XNjC4b8KVok4uw5RftR38Wgp2BFwql; expires=Thu, 23-Jul-2015 10:25:33 GMT; Max-Age=31449600; Path=/
X-Csrf-Token: i8XNjC4b8KVok4uw5RftR38Wgp2BFwql
The CSRF token cookie must not have httpOnly flag, as it is intended to be read by the JavaScript by design.
Javascript copies cookie into header. App checks this.
JavaScript running from a rogue file or email will not be able to read it and copy into the custom header. Even though the csrf-token cookie will be automatically sent with the rogue request, the server will be still expecting a valid X-Csrf-Token header.

*/

import PerfectHTTP
import SwiftString

public class CSRFSecurity {

	init(){}

	public static func checkHeaders(_ request: HTTPRequest) -> Bool {
		// boiled down so it's more testable
		return CSRFSecurity.isValid(origin: CSRFSecurity.getOrigin(request), host: CSRFSecurity.getHost(request))
	}

	static func isValid(origin: String, host: String) -> Bool {

		// If both origin and referrer are empty, dropkick as recommended by OWASP
		if origin.isEmpty {
			print("CSRF WARNING: CSRFSecurity.checkHeaders FAIL origin.isEmpty")
			return false
		}
		if SessionConfig.CSRFacceptableHostnames.count > 0 {
			// Check if acceptableHostnames has been prefilled. If yes, use that, else use the host
			for check in SessionConfig.CSRFacceptableHostnames {
				// Support for wildcards to come.
				if check == origin { return true }
			}
		}
		if host.isEmpty {
			print("CSRF WARNING: CSRFSecurity.checkHeaders FAIL host.isEmpty")
			return false
		}
		if host == origin { return true }

		print("CSRF WARNING: CSRFSecurity.checkHeaders FAIL host \(host) != origin \(origin)")
		return false
	}

	// Determine Origin
	static func getOrigin(_ request: HTTPRequest) -> String {
		if let origin = request.header(.origin), !(origin as String).isEmpty {
			return killhttp(origin as String)
		} else if let referer = request.header(.referer), !(referer as String).isEmpty {
			return killhttp(referer as String)
		} else if let xForwardedFor = request.header(.xForwardedFor), !(xForwardedFor as String).isEmpty {
			return killhttp(xForwardedFor as String)
		}
		return ""
	}

	// Determine Host
	static func getHost(_ request: HTTPRequest) -> String {
		if let host = request.header(.host), !(host as String).isEmpty {
			return killhttp(host as String)
		} else if let xForwardedHost = request.header(.xForwardedHost), !(xForwardedHost as String).isEmpty {
			return killhttp(xForwardedHost as String)
		}
		return ""
	}

	static func killhttp(_ str: String) -> String {
		var strr = str
		strr = strr.chompLeft("http://")
		strr = strr.chompLeft("https://")
		return strr
	}
}
