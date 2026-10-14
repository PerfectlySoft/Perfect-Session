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
