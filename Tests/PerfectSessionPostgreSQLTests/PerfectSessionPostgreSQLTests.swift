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

    func getDriver() async -> PostgreSQLSessionDriver {
        PostgreSQLSessionConnector.host     = ProcessInfo.processInfo.environment["PG_HOST"]     ?? "localhost"
        PostgreSQLSessionConnector.username = ProcessInfo.processInfo.environment["PG_USER"]     ?? "postgres"
        PostgreSQLSessionConnector.password = ProcessInfo.processInfo.environment["PG_PASSWORD"] ?? ""
        PostgreSQLSessionConnector.database = ProcessInfo.processInfo.environment["PG_DATABASE"] ?? "perfect_sessions_test"
        PostgreSQLSessionConnector.port     = Int(ProcessInfo.processInfo.environment["PG_PORT"] ?? "") ?? 5432
        PostgreSQLSessionConnector.table    = "test_sessions"
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
