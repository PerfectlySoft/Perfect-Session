import Testing
import Foundation
@testable import PerfectSessionSQLite
import PerfectSessionCore
import PerfectSQLite

/// Live-test settings, outside the suite so its traits can refer to them.
enum SQLiteLive {
    static let sqliteEnabled = ProcessInfo.processInfo.environment["SQLITE_TESTS"] == "1"
}

// Serialized: each test sets the connector's global settings.
@Suite(.serialized, .enabled(if: SQLiteLive.sqliteEnabled, "set SQLITE_TESTS=1 to run")) struct PerfectSessionSQLiteTests {

    /// Whether a row is stored for **token**, read directly: resume() refuses expired sessions
    /// whether or not clean() deleted them.
    func isStored(_ token: String) throws -> Bool {
        let db = try SQLite(SQLiteSessionConnector.databasePath)
        defer { db.close() }
        var found = false
        try db.forEachRow(statement: #"SELECT 1 FROM "test_sessions" WHERE token = ?"#,
                          doBindings: { try $0.bind(position: 1, token) },
                          handleRow: { _, _ in found = true })
        return found
    }

    func getDriver() async -> SQLiteSessionDriver {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfect_session_test_\(Int.random(in: 1..<999999)).db")
            .path
        SQLiteSessionConnector.databasePath = tmp
        SQLiteSessionConnector.table        = "test_sessions"
        let driver = SQLiteSessionDriver()
        await driver.setup()
        return driver
    }

    @Test func createAndResume() async throws {
        let driver = await getDriver()
        let session = await driver.create(ipaddress: "127.0.0.1", useragent: "SQLiteTest/1.0")
        #expect(!session.token.isEmpty)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.token == session.token)
        #expect(resumed.ipaddress == "127.0.0.1")
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
        session.userid = "sqlite-user-1"
        session.data["note"] = "hello"
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "sqlite-user-1")
        #expect(resumed.data["note"] as? String == "hello")
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

    @Test func timesPast32BitsRoundTrip() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle = Int.max
        await driver.save(session)
        await driver.clean()
        #expect(try await driver.resume(token: session.token).idle == Int.max)
        await driver.destroy(token: session.token)
    }

    /// resume() used to return an expired session (until clean() ran), leaving the check to
    /// the caller.
    @Test func resumeRejectsExpired() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle = -10   // save() renews `updated`, so expire it through idle
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
        await driver.destroy(token: session.token)
    }

    @Test func clean() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle = -10   // save() renews `updated`, so expire it through idle
        await driver.save(session)
        #expect(try isStored(session.token))
        await driver.clean()
        #expect(!(try isStored(session.token)))
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

    /// One value JSON can't hold used to make the drivers save empty data, CSRF token included,
    /// while the user stayed signed in.
    @Test func nonJSONValueDropsOnlyThatKey() async throws {
        let driver = await getDriver()
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
        let driver = await getDriver()
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
        let driver = await getDriver()
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
        let driver = await getDriver()
        var session = await driver.create()
        session.created -= 1000
        await driver.save(session)
        let fresh = await driver.regenerate(session)
        #expect(fresh.created == session.created)
        #expect(try await driver.resume(token: fresh.token).created == session.created)
        await driver.destroy(token: fresh.token)
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

    @Test func dataRoundTrip() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.data["string"] = "world"
        session.data["number"] = 42
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.data["string"] as? String == "world")
        #expect(resumed.data["number"] as? Int == 42)
        await driver.destroy(token: session.token)
    }
}

/// CI sets SESSION_REQUIRE_LIVE=1, so a job that forgets SQLITE_TESTS fails rather than passing with
/// the live suite skipped.
@Test func sqliteLiveTestsRunWhenRequired() {
    let required = ProcessInfo.processInfo.environment["SESSION_REQUIRE_LIVE"] == "1"
    #expect(!required || SQLiteLive.sqliteEnabled, "SESSION_REQUIRE_LIVE=1 but SQLITE_TESTS is not 1")
}
