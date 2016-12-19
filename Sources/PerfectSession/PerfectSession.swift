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

import Foundation

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
	public var idle			= SessionConfig.idle
	/// Data held in storage associated with session
	public var data			= [String: Any]()

	/// When creating a new session, the "created" and "updated" properties are set
	public init(){
		created = getNow()
		updated = getNow()
	}

	public func tojson() -> String {
		do {
			return try data.jsonEncodedString()
		} catch {
			return "{}"
		}
	}

	public mutating func fromjson(_ str : String) {
		data = try! str.jsonDecode() as! [String : Any]
	}

	/// updates the "updated" property
	public mutating func touch() {
		updated = getNow()
	}

	/// Compares the timestamps and idle to determine if session has expired
	public func isValid() -> Bool {
		if (updated + idle) > getNow() {
			return true
		}
		return false
	}

	private func getNow() -> Int {
		return Int(Date().timeIntervalSince1970)
	}
}






