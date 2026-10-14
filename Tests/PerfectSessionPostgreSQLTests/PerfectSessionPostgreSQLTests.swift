import Testing
import Foundation
@testable import PerfectSessionPostgreSQL
import PerfectSessionCore
import PerfectPostgreSQL

/// Live-test settings, outside the suite so its traits can refer to them.
enum PostgreSQLLive {
    static let pgEnabled = ProcessInfo.processInfo.environment["PG_TESTS"] == "1"
}

// Serialized: each test sets the connector's global settings.
@Suite(.serialized, .enabled(if: PostgreSQLLive.pgEnabled, "set PG_TESTS=1 to run against a server")) struct PerfectSessionPostgreSQLTests {

    /// Drops the test table once per run, so setup() creates it with the current schema.
    static let freshTable: Void = {
        let db = PGConnection()
        defer { db.close() }
        if db.connectdb(PostgreSQLSessionConnector.connectionString()) == .ok {
            db.exec(statement: #"DROP TABLE IF EXISTS "test_sessions""#).clear()
        }
    }()

    /// Whether a row is stored for **token**, read directly: resume() refuses expired sessions
    /// whether or not clean() deleted them.
    func isStored(_ token: String) -> Bool {
        let db = PGConnection()
        defer { db.close() }
        guard db.connectdb(PostgreSQLSessionConnector.connectionString()) == .ok else { return false }
        let result = db.exec(statement: #"SELECT 1 FROM "test_sessions" WHERE token = $1"#, params: [token])
        defer { result.clear() }
        return result.numTuples() > 0
    }

    func getDriver() async -> PostgreSQLSessionDriver {
        PostgreSQLSessionConnector.host     = ProcessInfo.processInfo.environment["PG_HOST"]     ?? "localhost"
        PostgreSQLSessionConnector.username = ProcessInfo.processInfo.environment["PG_USER"]     ?? "postgres"
        PostgreSQLSessionConnector.password = ProcessInfo.processInfo.environment["PG_PASSWORD"] ?? ""
        PostgreSQLSessionConnector.database = ProcessInfo.processInfo.environment["PG_DATABASE"] ?? "perfect_sessions_test"
        PostgreSQLSessionConnector.port     = Int(ProcessInfo.processInfo.environment["PG_PORT"] ?? "") ?? 5432
        PostgreSQLSessionConnector.table    = "test_sessions"
        Self.freshTable
        let driver = PostgreSQLSessionDriver()
        await driver.setup()
        return driver
    }

    @Test func createAndResume() async throws {
        let driver = await getDriver()
        let session = await driver.create(ipaddress: "192.168.1.1", useragent: "TestAgent/1.0")
        #expect(!session.token.isEmpty)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.token == session.token)
        #expect(resumed.ipaddress == "192.168.1.1")
        #expect(resumed._state == "resume")
        await driver.destroy(token: session.token)
    }

    @Test func resumeMissing() async {
        let driver = await getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.userid = "pg-user-1"
        session.data["score"] = 99
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "pg-user-1")
        #expect(resumed.data["score"] as? Int == 99)
        await driver.destroy(token: session.token)
    }

    @Test func destroy() async {
        let driver = await getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func saveAfterDestroyDoesNotResurrect() async {
        let driver = await getDriver()
        var session = await driver.create()
        session.userid = "logged-out"
        await driver.destroy(token: session.token)
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    /// The columns were 32-bit: an idle time past Int32.max failed to store, timestamps stop at
    /// 2038, and clean() failed outright (integer out of range) once any row's updated + idle
    /// passed Int32.max.
    @Test func timesPast32BitsRoundTrip() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle = 3_000_000_000
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.idle == 3_000_000_000)
        #expect(resumed.created == session.created)
        await driver.clean()
        _ = try await driver.resume(token: session.token)

        session.idle = Int.max
        await driver.save(session)
        var expired = await driver.create()
        expired.idle = 1
        expired.updated -= 10
        await driver.save(expired)
        await driver.clean()
        #expect(try await driver.resume(token: session.token).idle == Int.max)
        #expect(!isStored(expired.token))
        await driver.destroy(token: session.token)
    }

    /// resume() used to return an expired session (until clean() ran), leaving the check to
    /// the caller.
    @Test func resumeRejectsExpired() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle    = 1
        session.updated = Int(Date().timeIntervalSince1970) - 10
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
        await driver.destroy(token: session.token)
    }

    @Test func clean() async {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle    = 1
        session.updated = Int(Date().timeIntervalSince1970) - 10
        await driver.save(session)
        #expect(isStored(session.token))
        await driver.clean()
        #expect(!(isStored(session.token)))
    }

    /// Under trust auth any password is accepted, so this shows the URI still parses.
    @Test func passwordWithReservedCharactersConnects() async {
        _ = await getDriver()
        let saved = PostgreSQLSessionConnector.password
        defer { PostgreSQLSessionConnector.password = saved }
        PostgreSQLSessionConnector.password = saved.isEmpty ? "p@ss/w:rd?x#1" : saved
        guard saved.isEmpty else { return }
        let db = PGConnection()
        defer { db.close() }
        #expect(db.connectdb(PostgreSQLSessionConnector.connectionString()) == .ok, "\(db.errorMessage())")
    }

    /// Tokens and data are bound as parameters, so SQL in them is just text. (NUL isn't covered:
    /// PostgreSQL text can't hold it and SQLite text binding stops at it; see the README.)
    @Test(arguments: ["' OR '1'='1", "x' OR 1=1 -- ", "x`; DROP TABLE `test_sessions`; --",
                      "x\"; DROP TABLE \"test_sessions\"; --", "%", "\\", "emoji 😀 and é"])
    func sqlInTokensIsJustText(_ token: String) async throws {
        let driver = await getDriver()
        var other = await driver.create()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: token)
        }
        await driver.destroy(token: token)
        other.userid = token
        other.data[token] = token
        await driver.save(other)
        let resumed = try await driver.resume(token: other.token)
        #expect(resumed.userid == token, "\(token.debugDescription) became \(resumed.userid.debugDescription)")
        #expect(resumed.data[token] as? String == token, "\(token.debugDescription)")
        await driver.destroy(token: other.token)
    }

    /// Concurrent saves and resumes of one session: last writer wins, nothing is corrupted or lost.
    @Test func concurrentSaveAndResume() async throws {
        let driver = await getDriver()
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

    @Test func regenerateMovesSessionToNewToken() async throws {
        let driver = await getDriver()
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

    /// Fails, rather than letting the other tests pass vacuously, when the server can't be reached.
    @Test func serverIsReachable() async {
        _ = await getDriver()
        let db = PGConnection()
        defer { db.close() }
        #expect(db.connectdb(PostgreSQLSessionConnector.connectionString()) == .ok,
                "can't reach PostgreSQL: \(db.errorMessage())")
    }
}

/// CI sets SESSION_REQUIRE_LIVE=1, so a job that forgets PG_TESTS fails rather than passing with
/// the live suite skipped.
@Test func postgreSQLLiveTestsRunWhenRequired() {
    let required = ProcessInfo.processInfo.environment["SESSION_REQUIRE_LIVE"] == "1"
    #expect(!required || PostgreSQLLive.pgEnabled, "SESSION_REQUIRE_LIVE=1 but PG_TESTS is not 1")
}

/// connectionString() percent-encoded with .urlQueryAllowed, which leaves "/", "@", ":" and "?"
/// alone, so a password containing one broke the URI.
@Test func postgreSQLConnectionStringEncodesReservedCharacters() {
    #expect(PostgreSQLSessionConnector.connectionString(
        username: "us:er", password: "p@ss/w:rd?x=1&y#z%", host: "db.example.com", port: 5433,
        database: "my db/x") ==
        "postgresql://us%3Aer:p%40ss%2Fw%3Ard%3Fx%3D1%26y%23z%25@db.example.com:5433/my%20db%2Fx")
    #expect(PostgreSQLSessionConnector.connectionString(
        username: "u", password: "", host: "[::1]", port: 5432, database: "d") == "postgresql://u:@[::1]:5432/d")
    #expect(PostgreSQLSessionConnector.connectionString(
        username: "u", password: "", host: "/var/run/postgresql", port: 5432, database: "d") ==
        "postgresql://u:@%2Fvar%2Frun%2Fpostgresql:5432/d")
}
