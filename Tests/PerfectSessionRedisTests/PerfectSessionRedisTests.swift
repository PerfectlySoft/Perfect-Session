import Testing
import Foundation
@testable import PerfectSessionRedis
import PerfectSessionCore

@Suite struct PerfectSessionRedisTests {

    static let redisEnabled = ProcessInfo.processInfo.environment["REDIS_TESTS"] == "1"

    func getDriver() -> RedisSessionDriver {
        RedisSessionConnector.host     = ProcessInfo.processInfo.environment["REDIS_HOST"]     ?? "127.0.0.1"
        RedisSessionConnector.port     = Int(ProcessInfo.processInfo.environment["REDIS_PORT"] ?? "6379") ?? 6379
        RedisSessionConnector.password = ProcessInfo.processInfo.environment["REDIS_PASSWORD"] ?? ""
        return RedisSessionDriver()
    }

    @Test func createAndResume() async throws {
        guard Self.redisEnabled else { return }
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
        guard Self.redisEnabled else { return }
        let driver = getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        guard Self.redisEnabled else { return }
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

    @Test func destroy() async {
        guard Self.redisEnabled else { return }
        let driver = getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }
}
