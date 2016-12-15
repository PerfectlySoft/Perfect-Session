//
//  SessionManager.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2016-12-14.
//
//


/// PerfectSessionManager is a component that manages sessions. 
/// Create a class conforming to this protocol that saves, resumes and destroys session objects.
public protocol PerfectSessionManager {
	/// Retrieves the session
	func resume(token: String) throws -> PerfectSession

	/// Saves a session.
	func save(session: PerfectSession)

	/// Destroys the session.
	func destroy(token: String)
}

public struct InvalidSessionError: Error {
	public let description = "Invalid session ID"

	public init() {}
}
