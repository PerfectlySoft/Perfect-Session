import Testing
import Foundation
@testable import PerfectSessionPostgreSQL
import PerfectSessionCore

@Suite struct PerfectSessionPostgreSQLTests {

    static let pgEnabled = ProcessInfo.processInfo.environment["PG_TESTS"] == "1"

    func getDriver() async -> PostgreSQLSessionDriver {
        PostgreSQLSessionConnector.host     = ProcessInfo.processInfo.environment["PG_HOST"]     ?? "localhost"
        PostgreSQLSessionConnector.username = ProcessInfo.processInfo.environment["PG_USER"]     ?? "postgres"
        PostgreSQLSessionConnector.password = ProcessInfo.processInfo.environment["PG_PASSWORD"] ?? ""
        PostgreSQLSessionConnector.database = ProcessInfo.processInfo.environment["PG_DATABASE"] ?? "perfect_sessions_test"
        PostgreSQLSessionConnector.table    = "test_sessions"
        let driver = PostgreSQLSessionDriver()
        await driver.setup()
        return driver
    }

    @Test func createAndResume() async throws {
        guard Self.pgEnabled else { return }
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
        guard Self.pgEnabled else { return }
        let driver = await getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        guard Self.pgEnabled else { return }
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
        guard Self.pgEnabled else { return }
        let driver = await getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func clean() async {
        guard Self.pgEnabled else { return }
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
}
