//
//  PerfectSession.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//	Copyright (C) 2016 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

/*	Change History
====
0.0.6
Added IP Address, USer Agent storage
Added isValid checks for IP And UA
*/

import Foundation
import PerfectHTTP

/// Holds the session information in memory for duration of request
public struct PerfectSession {
	/// Token (session id)
	public var token			= ""
	/// Associated UserID. Optional to populate
	public var userid			= ""
	/// Date created, as an Int
	public var created			= 0
	/// Date updated, as an Int
	public var updated			= 0
	/// Idle time set at last update
	public var idle				= SessionConfig.idle
	/// Data held in storage associated with session
	public var data				= [String: Any]()


	/// IP Address of Session
	public var ipaddress		= ""

	/// UserAgent of Session
	public var useragent		= ""

	/// Session state
	public var _state			= "recover"

	/// Session state
	public var _isOAuth2		= SessionConfig.isOAuth2

	/// When creating a new session, the "created" and "updated" properties are set
	public init(){
		created = getNow()
		updated = getNow()
	}

	/// Makes a JSON Encoded string
	public func tojson() -> String {
		do {
			return try data.jsonEncodedString()
		} catch {
			print(error)
			return "{}"
		}
	}

	/// Sets the data property to a [String:Any] from JSON
	public mutating func fromjson(_ str : String) {
		do {
			data = try str.jsonDecode() as! [String : Any]
		} catch {
			print(error)
		}
	}

	/// updates the "updated" property
	public mutating func touch() {
		updated = getNow()
	}

	/// Compares the timestamps and idle to determine if session has expired
	public func isValid(_ request:HTTPRequest) -> Bool {
		if (updated + idle) > getNow() {
			if SessionConfig.IPAddressLock {
				// set forwarded-for (comes from well-behaving load balancers)
				let ff = request.header(.xForwardedFor) ?? ""

				if !ff.isEmpty && ff != ipaddress {
					// if ff is not empty, and it doesn't match ipaddress
					return false

				} else if ff.isEmpty && request.remoteAddress.host != ipaddress {
					// not an x-forwarded-for, and the ip adress is not correct
					return false
				}
			}

			if SessionConfig.userAgentLock && request.header(.userAgent) != useragent {
				return false
			}
			return true
		}
		return false
	}

	private func getNow() -> Int {
		return Int(Date().timeIntervalSince1970)
	}

	public mutating func setCSRF(){
		let t = data["csrf"] as? String ?? ""
		if t.isEmpty { data["csrf"] = UUID().uuidString }
	}
}






