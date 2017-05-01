//
//  AuthFilters.swift
//  PerfectSession
//
//  Created by Jonathan Guthrie on 2017-04-28.
//
//

import PerfectHTTP
import PerfectHTTPServer
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

	/// Accept an auth config via init.
	//	public init(_ cfg: AuthenticationConfig) {
	//		authenticationConfig = cfg
	//	}

	/// Perform the filtering, with a callback allowing continuation of request, or galting immediately.
	//	public static func filter(data: [String:Any]) throws -> HTTPRequestFilter {
	////	public func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
	//
	//		//		guard let denied = authenticationConfig.denied else {
	//		//			callback(.continue(request, response))
	//		//			return
	//		//		}
	//		var checkAuth = false
	//		let wildcardInclusions = AuthFilter.authenticationConfig.inclusions.filter({$0.contains("*")})
	//		let wildcardExclusions = AuthFilter.authenticationConfig.exclusions.filter({$0.contains("*")})
	//
	//		// check if specifically in inclusions
	//		if authenticationConfig.inclusions.contains(request.path) { checkAuth = true }
	//		// check if covered by a wildcard
	//		for wInc in wildcardInclusions {
	//			if request.path.startsWith(wInc.split("*")[0]) { checkAuth = true }
	//		}
	//
	//		// ignore check if sepecified in exclusions
	//		if authenticationConfig.exclusions.contains(request.path) { checkAuth = false }
	//		// check if covered by a wildcard
	//		for wInc in wildcardExclusions {
	//			if request.path.startsWith(wInc.split("*")[0]) { checkAuth = false }
	//		}
	//
	//		if checkAuth && !(request.session?.userid ?? "").isEmpty {
	//			callback(.continue(request, response))
	//			return
	//		} else if checkAuth {
	//			response.status = .unauthorized
	//			callback(.halt(request, response))
	//			return
	//		}
	//		callback(.continue(request, response))
	//	}

	public static func filter(data: [String:Any]) throws -> HTTPRequestFilter {

		struct filterRequest: HTTPRequestFilter {

			func filter(request: HTTPRequest, response: HTTPResponse, callback: (HTTPRequestFilterResult) -> ()) {
				var checkAuth = false
				let wildcardInclusions = AuthFilter.authenticationConfig.inclusions.filter({$0.contains("*")})
				let wildcardExclusions = AuthFilter.authenticationConfig.exclusions.filter({$0.contains("*")})

				// check if specifically in inclusions
				if AuthFilter.authenticationConfig.inclusions.contains(request.path) { checkAuth = true }
				// check if covered by a wildcard
				for wInc in wildcardInclusions {
					if request.path.startsWith(wInc.split("*")[0]) { checkAuth = true }
				}

				// ignore check if sepecified in exclusions
				if AuthFilter.authenticationConfig.exclusions.contains(request.path) { checkAuth = false }
				// check if covered by a wildcard
				for wInc in wildcardExclusions {
					if request.path.startsWith(wInc.split("*")[0]) { checkAuth = false }
				}

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
