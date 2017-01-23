//
//  http.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

import PerfectHTTP
import Foundation

public extension HTTPRequest {
	public(set) public var session: PerfectSession? {
		get {
			return scratchPad["PerfectSession"] as? PerfectSession
		}
		set {
			scratchPad["PerfectSession"] = newValue
		}
	}
}

struct SessionHeader {
	// https://www.w3.org/TR/WD-session-id
	//Session-Id: SID:ANON:w3.org:j6oAOxCWZh/CD723LGeXlf-01 - SID:type:realm:identifier
	let headerValue: String

	init?(value: String?) {
		guard let value = value else { return nil }
		headerValue = value
	}

	var sessionid: String? {
	let parts = headerValue.components(separatedBy: ":")
		if parts.count < 4 { return nil }
		return parts[3]
	}
}

extension HTTPRequest {
	var sessionid: SessionHeader? {
		return SessionHeader(value: self.header(.custom(name: "Session-Id")))
	}

	public func getCookie(name: String) -> String? {
		for (cookieName, payload) in self.cookies {
			if name == cookieName {
				return payload
			}
		}
		return nil
	}
}
