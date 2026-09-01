import Testing
import Foundation
@testable import PerfectSessionMySQL
import PerfectSessionCore

@Suite struct PerfectSessionMySQLTests {

    static let mysqlEnabled = ProcessInfo.processInfo.environment["MYSQL_TESTS"] == "1"

    func getDriver() async -> MySQLSessionDriver {
        MySQLSessionConnector.host     = ProcessInfo.processInfo.environment["MYSQL_HOST"]     ?? "localhost"
        MySQLSessionConnector.username = ProcessInfo.processInfo.environment["MYSQL_USER"]     ?? "root"
        MySQLSessionConnector.password = ProcessInfo.processInfo.environment["MYSQL_PASSWORD"] ?? ""
        MySQLSessionConnector.database = ProcessInfo.processInfo.environment["MYSQL_DATABASE"] ?? "perfect_sessions_test"
        MySQLSessionConnector.table    = "test_sessions"
        let driver = MySQLSessionDriver()
        await driver.setup()
        return driver
    }

    @Test func createAndResume() async throws {
        guard Self.mysqlEnabled else { return }
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
        guard Self.mysqlEnabled else { return }
        let driver = await getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        guard Self.mysqlEnabled else { return }
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
        guard Self.mysqlEnabled else { return }
        let driver = await getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func clean() async {
        guard Self.mysqlEnabled else { return }
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
