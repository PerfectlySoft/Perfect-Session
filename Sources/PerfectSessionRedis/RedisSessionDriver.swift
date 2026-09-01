import Foundation
import PerfectRedis
import PerfectSessionCore
import Logging

private let logger = Logger(label: "perfect.session.redis")

public struct RedisSessionConnector: Sendable {
    nonisolated(unsafe) public static var host: String     = "127.0.0.1"
    nonisolated(unsafe) public static var password: String = ""
    nonisolated(unsafe) public static var port: Int        = 6379
    private init() {}
}

public final class RedisSessionDriver: SessionDriver, @unchecked Sendable {
    public init() {}

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = UUID().uuidString
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        guard let json = encode(session) else { return session }
        do {
            let client = try await connect()
            _ = try await client.set(
                key: session.token, value: .string(json),
                expires: Double(SessionConfig.idle)
            )
            try? await client.close()
        } catch {
            logger.error("session create failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let client = try await connect()
        do {
            let response = try await client.get(key: token)
            try? await client.close()
            guard let json = response.string, !json.isEmpty else { throw InvalidSessionError() }
            guard var session = decode(token: token, json: json) else { throw InvalidSessionError() }
            session._state = "resume"
            return session
        } catch let e as InvalidSessionError {
            throw e
        } catch {
            try? await client.close()
            throw InvalidSessionError()
        }
    }

    public func save(_ session: PerfectSession) async {
        var s = session
        s.touch()
        guard let json = encode(s) else { return }
        do {
            let client = try await connect()
            _ = try await client.set(
                key: s.token, value: .string(json),
                expires: Double(SessionConfig.idle)
            )
            try? await client.close()
        } catch {
            logger.error("session save failed: \(error)", metadata: ["eventid": "\(s.token)"])
        }
    }

    public func destroy(token: String) async {
        do {
            let client = try await connect()
            try await client.delete(keys: token)
            try? await client.close()
        } catch {
            logger.error("session destroy failed: \(error)", metadata: ["eventid": "\(token)"])
        }
    }

    // MARK: - Private helpers

    private func connect() async throws -> RedisClient {
        let id = RedisClientIdentifier(
            withHost: RedisSessionConnector.host,
            port: RedisSessionConnector.port,
            password: RedisSessionConnector.password
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
            "data":      session.data,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: dict),
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
