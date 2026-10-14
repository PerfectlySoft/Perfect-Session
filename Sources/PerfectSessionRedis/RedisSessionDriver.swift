import Foundation
import PerfectRedis
import PerfectSessionCore
import Logging

private let logger = Logger(label: "perfect.session.redis")

/// Connection settings used by `RedisSessionDriver`. Set them once at startup.
public struct RedisSessionConnector: Sendable {
    nonisolated(unsafe) public static var host: String     = "127.0.0.1"
    nonisolated(unsafe) public static var password: String = ""
    nonisolated(unsafe) public static var port: Int        = 6379
    /// Prepended to each token to make its Redis key. Tokens come from clients' cookies, so the
    /// prefix keeps a token from naming one of the application's own keys.
    nonisolated(unsafe) public static var keyPrefix: String = "perfect-session:"
    /// Seconds each Redis call may take (see Perfect-Redis's `RedisClientIdentifier`), or nil to
    /// wait indefinitely.
    nonisolated(unsafe) public static var commandTimeout: Double? = nil
    private init() {}
}

/// Stores each session as a JSON string under `keyPrefix + token`, with a TTL of the session's
/// `idle` seconds, renewed by every `save`. Each call opens its own connection.
public final class RedisSessionDriver: SessionDriver, Sendable {
    public init() {}

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = PerfectSession.newToken()
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        guard session.idle > 0 else {
            logger.error("session not stored: idle must be positive, not \(session.idle)")
            return session
        }
        guard let json = encode(session) else { return session }
        do {
            _ = try await withClient { client in
                try await client.set(key: self.key(session.token), value: .string(json),
                                     expires: Double(session.idle), ifNotExists: true)
            }
        } catch {
            logger.error("session create failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let response: RedisResponse
        do {
            response = try await withClient { try await $0.get(key: self.key(token)) }
        } catch {
            logger.error("session resume failed: \(error)", metadata: ["eventid": "\(token)"])
            throw InvalidSessionError()
        }
        guard let json = response.string, !json.isEmpty,
              var session = decode(token: token, json: json), !session.isExpired() else {
            throw InvalidSessionError()
        }
        session._state = "resume"
        session.setCSRF()   // a stored session without a CSRF token gets one
        return session
    }

    /// Updates a stored session and renews its TTL. A session that is no longer stored (it was
    /// destroyed or has expired) isn't stored again, so a save racing a logout can't bring the
    /// session back. A session whose `idle` is 0 or less is deleted.
    public func save(_ session: PerfectSession) async {
        var s = session
        s.touch()
        do {
            guard s.idle > 0 else {
                _ = try await withClient { try await $0.delete(keys: self.key(s.token)) }
                return
            }
            guard let json = encode(s) else { return }
            let token = s.token, idle = s.idle
            let reply = try await withClient { client in
                try await client.set(key: self.key(token), value: .string(json),
                                     expires: Double(idle), ifExists: true)
            }
            if reply.isNil {
                logger.debug("session save matched no session (destroyed or expired); not recreated",
                             metadata: ["eventid": "\(s.token)"])
            }
        } catch {
            logger.error("session save failed: \(error)", metadata: ["eventid": "\(s.token)"])
        }
    }

    public func destroy(token: String) async {
        do {
            _ = try await withClient { try await $0.delete(keys: self.key(token)) }
        } catch {
            logger.error("session destroy failed: \(error)", metadata: ["eventid": "\(token)"])
        }
    }

    // MARK: - Private helpers

    private func key(_ token: String) -> String {
        RedisSessionConnector.keyPrefix + token
    }

    /// Runs **body** on a new connection, then closes it.
    private func withClient<T: Sendable>(_ body: (RedisClient) async throws -> T) async throws -> T {
        let client = try await connect()
        do {
            let result = try await body(client)
            try? await client.close()
            return result
        } catch {
            try? await client.close()
            throw error
        }
    }

    private func connect() async throws -> RedisClient {
        let id = RedisClientIdentifier(
            withHost: RedisSessionConnector.host,
            port: RedisSessionConnector.port,
            password: RedisSessionConnector.password,
            commandTimeout: RedisSessionConnector.commandTimeout
        )
        return try await RedisClient.connect(withIdentifier: id)
    }

    private func encode(_ session: PerfectSession) -> String? {
        let dict: [String: Any] = [
            "userid":    session.userid,
            "created":   session.created,
            "updated":   session.updated,
            "idle":      session.idle,
            "ipaddress": session.ipaddress,
            "useragent": session.useragent,
            "data":      session.jsonSafeData(),
        ]
        guard JSONSerialization.isValidJSONObject(dict),
              let d = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    private func decode(token: String, json: String) -> PerfectSession? {
        guard let d = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        var s = PerfectSession()
        s.token     = token
        s.userid    = obj["userid"]    as? String ?? ""
        s.created   = obj["created"]   as? Int    ?? 0
        s.updated   = obj["updated"]   as? Int    ?? 0
        s.idle      = obj["idle"]      as? Int    ?? SessionConfig.idle
        s.ipaddress = obj["ipaddress"] as? String ?? ""
        s.useragent = obj["useragent"] as? String ?? ""
        if let data = obj["data"] as? [String: Any] { s.data = data }
        return s
    }
}
