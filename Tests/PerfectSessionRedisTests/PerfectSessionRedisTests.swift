import Testing
import Foundation
@testable import PerfectSessionRedis
import PerfectSessionCore
import PerfectRedis

/// Live-test settings, outside the suite so its traits can refer to them.
enum RedisLive {
    static let redisEnabled = ProcessInfo.processInfo.environment["REDIS_TESTS"] == "1"
}

// Serialized: each test sets the connector's global settings.
@Suite(.serialized, .enabled(if: RedisLive.redisEnabled, "set REDIS_TESTS=1 to run against a server")) struct PerfectSessionRedisTests {

    func getDriver() -> RedisSessionDriver {
        RedisSessionConnector.host     = ProcessInfo.processInfo.environment["REDIS_HOST"]     ?? "127.0.0.1"
        RedisSessionConnector.port     = Int(ProcessInfo.processInfo.environment["REDIS_PORT"] ?? "6379") ?? 6379
        RedisSessionConnector.password = ProcessInfo.processInfo.environment["REDIS_PASSWORD"] ?? ""
        return RedisSessionDriver()
    }

    @Test func createAndResume() async throws {
        let driver = getDriver()
        let session = await driver.create(ipaddress: "10.0.0.1", useragent: "RedisTest/1.0")
        #expect(!session.token.isEmpty)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.token == session.token)
        #expect(resumed.ipaddress == "10.0.0.1")
        #expect(resumed._state == "resume")
        await driver.destroy(token: session.token)
    }

    @Test func resumeMissing() async {
        let driver = getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.userid = "redis-user-1"
        session.data["flag"] = true
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "redis-user-1")
        #expect(resumed.data["flag"] as? Bool == true)
        await driver.destroy(token: session.token)
    }

    @Test func saveWithNonJSONValueDoesNotCrash() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.userid = "redis-user-2"
        session.data["when"] = Date()
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "redis-user-2")
        #expect(resumed.data.isEmpty)
        await driver.destroy(token: session.token)
    }

    @Test func destroy() async {
        let driver = getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    func rawClient() async throws -> RedisClient {
        try await RedisClient.connect(withIdentifier: RedisClientIdentifier(
            withHost: RedisSessionConnector.host, port: RedisSessionConnector.port,
            password: RedisSessionConnector.password, commandTimeout: 10))
    }

    /// A save racing a logout used to SET the key again and bring the session back.
    @Test func saveAfterDestroyDoesNotResurrect() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.userid = "logged-out"
        await driver.destroy(token: session.token)
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    /// The key's TTL follows the session's own idle time, not SessionConfig.idle.
    @Test func expiryFollowsSessionIdle() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.idle = 1
        await driver.save(session)
        try await Task.sleep(for: .milliseconds(1500))
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    /// An idle time of 0 or less used to store the session with no TTL at all.
    @Test func nonPositiveIdleDoesNotMakeASessionImmortal() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.idle = 0
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    /// Tokens come from the client's cookie. Session keys are namespaced, so a token can't name
    /// (and resume or delete) one of the application's own keys.
    @Test func tokenCannotReachOtherKeys() async throws {
        let driver = getDriver()
        let client = try await rawClient()
        let key = "app:user:\(UUID().uuidString)"
        _ = try await client.set(key: key, value: .string(#"{"userid":"admin","data":{}}"#))
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: key)
        }
        await driver.destroy(token: key)
        #expect(try await client.get(key: key).string != nil)
        _ = try await client.delete(keys: key)
        try await client.close()
    }

    /// Keys go to Redis as bulk strings, so separators, spaces and CR/LF in a token are just bytes.
    @Test(arguments: ["a b", "a:b", "x\r\nFLUSHALL\r\n", "*1\r\n$4\r\nPING", "", "\u{0}"])
    func awkwardTokensAreJustMissingSessions(_ token: String) async throws {
        let driver = getDriver()
        let client = try await rawClient()
        let canary = "canary:\(UUID().uuidString)"
        _ = try await client.set(key: canary, value: .string("alive"))
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: token)
        }
        await driver.destroy(token: token)
        #expect(try await client.get(key: canary).string == "alive")
        _ = try await client.delete(keys: canary)
        try await client.close()
    }

    @Test func keysAreNamespaced() async throws {
        let driver = getDriver()
        let session = await driver.create()
        let client = try await rawClient()
        #expect(try await client.get(key: RedisSessionConnector.keyPrefix + session.token).string != nil)
        #expect(try await client.get(key: session.token).isNil)
        try await client.close()
        await driver.destroy(token: session.token)
    }

    /// Fails, rather than letting the other tests pass vacuously, when the server can't be reached.
    @Test func serverIsReachable() async throws {
        _ = getDriver()
        let client = try await RedisClient.connect(withIdentifier: RedisClientIdentifier(
            withHost: RedisSessionConnector.host, port: RedisSessionConnector.port,
            password: RedisSessionConnector.password, commandTimeout: 10))
        let pong = try await client.ping()
        #expect(pong.string == "PONG")
        try await client.close()
    }
}

/// CI sets SESSION_REQUIRE_LIVE=1, so a job that forgets REDIS_TESTS fails rather than passing with
/// the live suite skipped.
@Test func redisLiveTestsRunWhenRequired() {
    let required = ProcessInfo.processInfo.environment["SESSION_REQUIRE_LIVE"] == "1"
    #expect(!required || RedisLive.redisEnabled, "SESSION_REQUIRE_LIVE=1 but REDIS_TESTS is not 1")
}
