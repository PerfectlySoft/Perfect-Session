import Testing
import Foundation
import Logging
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
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

    /// A Redis call that gets no reply gives up after RedisSessionConnector.commandTimeout,
    /// 5 seconds by default (it used to wait forever).
    @Test func commandTimeoutDefaultsToFiveSeconds() async throws {
        #expect(RedisSessionConnector.commandTimeout == 5)
        let driver = getDriver()
        let listener = try SilentListener()
        defer { listener.close() }
        RedisSessionConnector.host = "127.0.0.1"
        RedisSessionConnector.port = listener.port
        defer { _ = getDriver() }
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    _ = try await driver.resume(token: "anything")
                    return "resumed"
                } catch {
                    return "threw"
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return "still waiting"
            }
            let first = await group.next() ?? ""
            group.cancelAll()
            return first
        }
        let elapsed = clock.now - start
        #expect(outcome == "threw")
        #expect(elapsed >= .seconds(4) && elapsed < .seconds(9), "\(elapsed)")
    }

    /// An idle time near Int.max made SET's PX argument unrepresentable, so save() failed and
    /// the session's new data was lost.
    @Test(arguments: [Int.max, Int.max / 1000, 1 << 50])
    func hugeIdleStillSaves(_ idle: Int) async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.idle = idle
        session.data["saved"] = true
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.data["saved"] as? Bool == true)
        #expect(resumed.idle == idle)
        await driver.destroy(token: session.token)
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

    /// Concurrent saves and resumes of one session: last writer wins, nothing is corrupted or lost.
    @Test func concurrentSaveAndResume() async throws {
        let driver = getDriver()
        let session = await driver.create()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                group.addTask {
                    if i.isMultiple(of: 2) {
                        var copy = session
                        copy.data["n"] = i
                        await driver.save(copy)
                    } else {
                        _ = try await driver.resume(token: session.token)
                    }
                }
            }
            try await group.waitForAll()
        }
        let final = try await driver.resume(token: session.token)
        let n = try #require(final.data["n"] as? Int)
        #expect(n.isMultiple(of: 2) && (0..<40).contains(n))
        #expect(final.data["csrf"] as? String == session.data["csrf"] as? String)
        await driver.destroy(token: session.token)
    }

    /// One value JSON can't hold used to make the drivers save empty data, CSRF token included,
    /// while the user stayed signed in.
    @Test func nonJSONValueDropsOnlyThatKey() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.userid = "signed-in"
        session.data["kept"] = "yes"
        session.data["when"] = Date()
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "signed-in")
        #expect(resumed.data["kept"] as? String == "yes")
        #expect(resumed.data["when"] == nil)
        #expect(resumed.data["csrf"] as? String == session.data["csrf"] as? String)
        await driver.destroy(token: session.token)
    }

    /// A stored session without a CSRF token gets one when it's resumed.
    @Test func resumeRestoresMissingCSRF() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.data.removeValue(forKey: "csrf")
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect((resumed.data["csrf"] as? String)?.isEmpty == false)
        await driver.destroy(token: session.token)
    }

    /// save() renews the idle time: a session saved within every `idle` seconds stays alive
    /// past `idle` seconds from creation. Only Redis used to do this.
    @Test func saveRenewsIdle() async throws {
        let driver = getDriver()
        var session = await driver.create()
        // Times are whole seconds, so allow a second of rounding either way: 3 + 3 seconds is
        // past idle + 1 from creation, and 3 is under idle - 1 from each save.
        session.idle = 5
        await driver.save(session)
        try await Task.sleep(for: .seconds(3))
        session = try await driver.resume(token: session.token)
        await driver.save(session)
        try await Task.sleep(for: .seconds(3))
        _ = try await driver.resume(token: session.token)
        await driver.destroy(token: session.token)
    }

    /// regenerate() used to restart the absolute timeout: the new session got a new `created`.
    @Test func regenerateKeepsCreated() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.created -= 1000
        await driver.save(session)
        let fresh = await driver.regenerate(session)
        #expect(fresh.created == session.created)
        #expect(try await driver.resume(token: fresh.token).created == session.created)
        await driver.destroy(token: fresh.token)
    }

    @Test func regenerateMovesSessionToNewToken() async throws {
        let driver = getDriver()
        var session = await driver.create()
        session.userid = "user-before-login"
        session.data["cart"] = 3
        await driver.save(session)
        let fresh = await driver.regenerate(session)
        #expect(fresh.token != session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
        let resumed = try await driver.resume(token: fresh.token)
        #expect(resumed.userid == "user-before-login")
        #expect(resumed.data["cart"] as? Int == 3)
        #expect(resumed.data["csrf"] as? String == fresh.data["csrf"] as? String)
        #expect(resumed.data["csrf"] as? String != session.data["csrf"] as? String)
        await driver.destroy(token: fresh.token)
    }

    /// The key's TTL used to ignore SessionConfig.absoluteTimeout.
    @Test func ttlHonoursAbsoluteTimeout() {
        var s = PerfectSession()
        s.created = 10_000
        s.updated = 10_100
        s.idle = 3600
        #expect(RedisSessionDriver.ttl(s, absoluteTimeout: 0, now: 10_100) == 3600)
        #expect(RedisSessionDriver.ttl(s, absoluteTimeout: 500, now: 10_100) == 400)
        #expect(RedisSessionDriver.ttl(s, absoluteTimeout: 50, now: 10_100) == 1)
        s.idle = Int.max
        #expect(RedisSessionDriver.ttl(s, absoluteTimeout: 0, now: 10_100) == Double(RedisSessionDriver.maximumTTL))
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

/// Collects every log line, with its metadata, in this process.
final class CapturedLogs: @unchecked Sendable {
    static let shared = CapturedLogs()
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

struct CapturingLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    func log(event: LogEvent) {
        CapturedLogs.shared.append("\(event.message) \(event.metadata ?? [:]) \(metadata)")
    }
}

/// Failures used to log the full session token as `eventid`; a token in a log is a session
/// anyone with log access can take over. Runs in a child process so it can bootstrap logging.
@Test(.disabled(if: underThreadSanitizer, "exit tests abort under ThreadSanitizer"))
func redisLogsDoNotContainTokens() async {
    await #expect(processExitsWith: .success) {
        LoggingSystem.bootstrap { _ in CapturingLogHandler() }
        RedisSessionConnector.host = "127.0.0.1"
        RedisSessionConnector.port = 1   // nothing listens: every call fails and logs
        let driver = RedisSessionDriver()
        var session = await driver.create()
        session.data["x"] = 1
        await driver.save(session)
        _ = try? await driver.resume(token: session.token)
        await driver.destroy(token: session.token)
        let logs = CapturedLogs.shared.text
        let leaked = logs.contains(session.token)
        let identified = logs.contains(PerfectSession.logID(session.token))
        if leaked || !identified { print(logs) }
        exit(!leaked && identified ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

/// A TCP listener that never accepts or answers: connections complete in the kernel's backlog,
/// then nothing is ever sent back.
final class SilentListener: @unchecked Sendable {
    let fd: Int32
    let port: Int

    struct Failure: Error {}

    init() throws {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw Failure() }
        self.fd = fd
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && listen(fd, 16) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard bound else { throw Failure() }
        port = Int(UInt16(bigEndian: address.sin_port))
    }

    func close() {
        #if os(Linux)
        _ = Glibc.close(fd)
        #else
        _ = Darwin.close(fd)
        #endif
    }
}

/// Whether the ThreadSanitizer runtime is loaded. Exit tests abort under it (even one that only
/// calls exit(0)), so they're skipped there.
let underThreadSanitizer: Bool = {
    #if os(Linux)
    let defaultHandle: UnsafeMutableRawPointer? = nil          // RTLD_DEFAULT
    #else
    let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    #endif
    return dlsym(defaultHandle, "__tsan_init") != nil
}()
