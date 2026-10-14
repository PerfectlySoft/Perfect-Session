import Testing
import Foundation
@testable import PerfectSessionMySQL
import PerfectSessionCore
import PerfectMySQL

/// Live-test settings, outside the suite so its traits can refer to them.
enum MySQLLive {
    /// MYSQL_PORT is required too, so the tests never fall back to a developer's own server on 3306.
    static let port = Int(ProcessInfo.processInfo.environment["MYSQL_PORT"] ?? "")
    static let mysqlEnabled = ProcessInfo.processInfo.environment["MYSQL_TESTS"] == "1" && port != nil
}

// Serialized: each test sets the connector's global settings.
@Suite(.serialized, .enabled(if: MySQLLive.mysqlEnabled, "set MYSQL_TESTS=1 and MYSQL_PORT to run against a server")) struct PerfectSessionMySQLTests {

    /// Drops the test table once per run, so setup() creates it with the current schema.
    static let freshTable: Void = {
        let db = MySQL()
        if db.connect(host: MySQLSessionConnector.host, user: MySQLSessionConnector.username,
                      password: MySQLSessionConnector.password, db: MySQLSessionConnector.database,
                      port: UInt32(MySQLSessionConnector.port)) {
            _ = db.query(statement: "DROP TABLE IF EXISTS `test_sessions`")
        }
    }()

    /// Whether a row is stored for **token**, read directly: resume() refuses expired sessions
    /// whether or not clean() deleted them.
    func isStored(_ token: String) -> Bool {
        let db = MySQL()
        guard db.connect(host: MySQLSessionConnector.host, user: MySQLSessionConnector.username,
                         password: MySQLSessionConnector.password, db: MySQLSessionConnector.database,
                         port: UInt32(MySQLSessionConnector.port)),
              db.query(statement: "SELECT 1 FROM `test_sessions` WHERE token = '\(token)'"),
              let results = db.storeResults() else { return false }
        return results.numRows() > 0
    }

    func getDriver() async -> MySQLSessionDriver {
        MySQLSessionConnector.host     = ProcessInfo.processInfo.environment["MYSQL_HOST"]     ?? "localhost"
        MySQLSessionConnector.username = ProcessInfo.processInfo.environment["MYSQL_USER"]     ?? "root"
        MySQLSessionConnector.password = ProcessInfo.processInfo.environment["MYSQL_PASSWORD"] ?? ""
        MySQLSessionConnector.database = ProcessInfo.processInfo.environment["MYSQL_DATABASE"] ?? "perfect_sessions_test"
        MySQLSessionConnector.port     = MySQLLive.port ?? 0
        MySQLSessionConnector.table    = "test_sessions"
        Self.freshTable
        let driver = MySQLSessionDriver()
        await driver.setup()
        return driver
    }

    @Test func createAndResume() async throws {
        let driver = await getDriver()
        let session = await driver.create(ipaddress: "10.0.0.1", useragent: "TestAgent/1.0")
        #expect(!session.token.isEmpty)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.token == session.token)
        #expect(resumed.ipaddress == "10.0.0.1")
        #expect(resumed.useragent == "TestAgent/1.0")
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
        session.userid = "mysql-user-1"
        session.data["key"] = "value"
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "mysql-user-1")
        #expect(resumed.data["key"] as? String == "value")
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

    /// The columns were 32-bit: an idle time past Int32.max failed to store, and timestamps
    /// stop at 2038.
    @Test func timesPast32BitsRoundTrip() async throws {
        let driver = await getDriver()
        var session = await driver.create()
        session.idle = 3_000_000_000
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.idle == 3_000_000_000)
        #expect(resumed.created == session.created)
        #expect(resumed.updated == session.updated)
        await driver.clean()
        _ = try await driver.resume(token: session.token)

        // clean() still deletes expired sessions when another's updated + idle overflows BIGINT.
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

    /// Fails, rather than letting the other tests pass vacuously, when the server can't be reached.
    @Test func serverIsReachable() async {
        _ = await getDriver()
        let db = MySQL()
        let connected = db.connect(host: MySQLSessionConnector.host, user: MySQLSessionConnector.username,
                                   password: MySQLSessionConnector.password, db: MySQLSessionConnector.database,
                                   port: UInt32(MySQLSessionConnector.port))
        #expect(connected, "can't reach MySQL at \(MySQLSessionConnector.host):\(MySQLSessionConnector.port): \(db.errorMessage())")
    }
}

/// CI sets SESSION_REQUIRE_LIVE=1, so a job that forgets MYSQL_TESTS fails rather than passing with
/// the live suite skipped.
@Test func mysqlLiveTestsRunWhenRequired() {
    let required = ProcessInfo.processInfo.environment["SESSION_REQUIRE_LIVE"] == "1"
    #expect(!required || MySQLLive.mysqlEnabled, "SESSION_REQUIRE_LIVE=1 but MYSQL_TESTS is not 1")
}

@Test func mysqlLiveTestsHaveAPort() {
    let requested = ProcessInfo.processInfo.environment["MYSQL_TESTS"] == "1"
    #expect(!requested || MySQLLive.port != nil, "MYSQL_TESTS=1 needs MYSQL_PORT")
}
