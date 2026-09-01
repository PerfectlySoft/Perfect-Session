import Foundation

public struct InvalidSessionError: Error, Sendable {
    public let description = "Invalid or expired session"
    public init() {}
}

/// Backend-agnostic session storage protocol. All methods are async so Redis can use
/// native async/await; synchronous drivers conform naturally since sync satisfies async.
public protocol SessionDriver: Sendable {
    func create(ipaddress: String, useragent: String) async -> PerfectSession
    func resume(token: String) async throws -> PerfectSession
    func save(_ session: PerfectSession) async
    func destroy(token: String) async
    func clean() async
    func setup() async
}

extension SessionDriver {
    public func clean() async {}
    public func setup() async {}
}
