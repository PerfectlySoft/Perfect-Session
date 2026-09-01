import Foundation

/// Thread-safe in-memory session store. Useful for development and testing.
public final class MemorySessionDriver: SessionDriver, @unchecked Sendable {
    private var sessions = [String: PerfectSession]()
    private let lock = NSLock()

    public init() {}

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = UUID().uuidString
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        let t = session.token
        lock.withLock { sessions[t] = session }
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let found = lock.withLock { sessions[token] }
        guard var session = found else { throw InvalidSessionError() }
        session._state = "resume"
        return session
    }

    public func save(_ session: PerfectSession) async {
        lock.withLock { sessions[session.token] = session }
    }

    public func destroy(token: String) async {
        _ = lock.withLock { sessions.removeValue(forKey: token) }
    }

    public func clean() async {
        let now = Int(Date().timeIntervalSince1970)
        lock.withLock {
            sessions = sessions.filter { _, s in (s.updated + s.idle) > now }
        }
    }
}
