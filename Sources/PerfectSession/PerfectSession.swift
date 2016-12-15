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



/// Holds the session information in memory for duration of request
public struct PerfectSession {
	/// Token (session id)
	var token			= ""
	/// Associated UserID. Optional to populate
	var userid			= ""
	/// Date created, as an Int
	var created			= 0
	/// Date updated, as an Int
	var updated			= 0
	/// Idle time set at last update
	var idle			= SessionConfig.idle
	/// Data held in storage associated with session
	var data			= [String: Any]()

}






