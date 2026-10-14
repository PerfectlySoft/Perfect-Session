import Testing
import Foundation
@testable import PerfectSessionSQLite
import PerfectSessionCore

/// Live-test settings, outside the suite so its traits can refer to them.
enum SQLiteLive {
    static let sqliteEnabled = ProcessInfo.processInfo.environment["SQLITE_TESTS"] == "1"
}

// Serialized: each test sets the connector's global settings.
@Suite(.serialized, .enabled(if: SQLiteLive.sqliteEnabled, "set SQLITE_TESTS=1 to run")) struct PerfectSessionSQLiteTests {

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

    @Test func clean() async {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle    = 1
        session.updated = Int(Date().timeIntervalSince1970) - 10
        await driver.save(session)
        await driver.clean()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
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
