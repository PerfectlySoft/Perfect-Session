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
    /// Moves a session to a new token. See the default implementation.
    func regenerate(_ session: PerfectSession) async -> PerfectSession
}

extension SessionDriver {
    public func clean() async {}
    public func setup() async {}

    /// Moves **session**'s user, data and idle time to a newly created session with a new token
    /// and a new CSRF token, then destroys the old session. Call it whenever the user signs in,
    /// signs out to a guest session, or gains privileges, and send the client the new token:
    /// a token an attacker planted or saw beforehand (session fixation) then no longer works.
    ///
    /// The new session keeps the old one's IP address and user agent. If the backend can't store
    /// it, the returned session isn't stored (as with `create`), and the old one is destroyed.
    public func regenerate(_ session: PerfectSession) async -> PerfectSession {
        var fresh = await create(ipaddress: session.ipaddress, useragent: session.useragent)
        let csrf = fresh.data["csrf"]
        fresh.userid = session.userid
        fresh.idle   = session.idle
        fresh.data   = session.data
        fresh.data["csrf"] = csrf
        await save(fresh)
        await destroy(token: session.token)
        return fresh
    }
}
