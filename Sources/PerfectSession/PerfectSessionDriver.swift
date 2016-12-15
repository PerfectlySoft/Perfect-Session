//
//  PerfectSessionDriver.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//

public class PerfectSessionDriver {
	public var session = PerfectSession()

	public init(_ s: PerfectSession) { session = s }

	public func save() {
		if SessionConfig.storage == .memory { saveMemory() }
		else { saveDatabase() }
	}
	public func saveMemory() {
		// save to memory driver
	}
	open func saveDatabase() {
		// save to db driver
	}
}


