//
//  AuthFilters.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2017-04-28.
//
//

import PerfectHTTP
import SwiftString


/// Sets up the matrix of which routes are checked for authentication, and which are not.
public struct AuthenticationConfig {

	/// An array of routes that are checked for valid authentication.
	public var inclusions = [String]()

	/// An array of routes that will not be checked.
	public var exclusions = [String]()

	/// Unimplemented. Will optionally provide a location for access denied redirection.
	public var denied: String?

	public init() {}

	/// Add a route as a string to the array of inclusions
	public mutating func include(_ str: String) {
		inclusions.append(str)
	}
	/// Add a an array of strings (as routes) to the array of inclusions
	public mutating func include(_ arr: [String]) {
		inclusions += arr
	}
	/// Add a route as a string to the array of exclusions
	public mutating func exclude(_ str: String) {
		exclusions.append(str)
	}
	/// Add a an array of strings (as routes) to the array of exclusions
	public mutating func exclude(_ arr: [String]) {
		exclusions += arr
	}
}

/// Contains the filtering mechanism for determining valid authentication on routes.
public struct AuthFilter {

	/// The authentication configuration. Holds the routes to be included or excluded
	public static var authenticationConfig = AuthenticationConfig()

	public static func shouldWeAccept(_ path: String) -> Bool {
		var checkAuth = false

		let wildcardInclusions = AuthFilter.authenticationConfig.inclusions.filter({$0.contains("*")})
		let wildcardExclusions = AuthFilter.authenticationConfig.exclusions.filter({$0.contains("*")})

		// check if specifically in inclusions
		if AuthFilter.authenticationConfig.inclusions.contains(path) { checkAuth = true }
		// check if covered by a wildcard
		for wInc in wildcardInclusions {
			if path.startsWith(wInc.split("*")[0]) { checkAuth = true }
		}

		// ignore check if sepecified in exclusions
		if AuthFilter.authenticationConfig.exclusions.contains(path) { checkAuth = false }
		// check if covered by a wildcard
		for wInc in wildcardExclusions {
			if path.startsWith(wInc.split("*")[0]) { checkAuth = false }
		}
		//print("checkAuth for \(path): \(checkAuth)")
		return checkAuth
	}

	public static func filter(data: [String:Any]) throws -> HTTPRequestFilter {

		struct filterRequest: HTTPRequestFilter {

			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				let checkAuth = AuthFilter.shouldWeAccept(request.path)

				if checkAuth && !(request.session?.userid ?? "").isEmpty {
					callback(.continue(request, response))
					return
				} else if checkAuth {
					response.status = .unauthorized
					callback(.halt(request, response))
					return
				}

				callback(.continue(request, response))
			}
		}
		return filterRequest()
	}
}
