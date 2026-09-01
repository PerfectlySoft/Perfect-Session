import Testing
import Foundation
@testable import PerfectSessionCore

@Suite struct PerfectSessionCoreTests {

    @Test func sessionInit() {
        let s = PerfectSession()
        #expect(!s.token.isEmpty == false) // token is set by driver, not init
        #expect(s.created > 0)
        #expect(s.updated > 0)
        #expect(s.idle == SessionConfig.idle)
        #expect(s._state == "recover")
    }

    @Test func sessionJSONRoundTrip() {
        var s = PerfectSession()
        s.data["name"]   = "Alice"
        s.data["count"]  = 42
        s.data["active"] = true
        let json = s.tojson()
        #expect(!json.isEmpty)
        var s2 = PerfectSession()
        s2.fromjson(json)
        #expect(s2.data["name"] as? String == "Alice")
        #expect(s2.data["count"] as? Int == 42)
        #expect(s2.data["active"] as? Bool == true)
    }

    @Test func sessionToJsonEmptyData() {
        let s = PerfectSession()
        #expect(s.tojson() == "{}")
    }

    @Test func sessionFromJsonBadInput() {
        var s = PerfectSession()
        s.data["key"] = "before"
        s.fromjson("not-valid-json")
        // data unchanged on bad input
        #expect(s.data["key"] as? String == "before")
    }

    @Test func sessionSetCSRF() {
        var s = PerfectSession()
        s.setCSRF()
        let csrf = s.data["csrf"] as? String ?? ""
        #expect(!csrf.isEmpty)
        // calling again should not change it
        let before = csrf
        s.setCSRF()
        #expect(s.data["csrf"] as? String == before)
    }

    @Test func sessionTouch() throws {
        var s = PerfectSession()
        let before = s.updated
        try #require(before > 0)
        s.touch()
        #expect(s.updated >= before)
    }

    @Test func sessionIsValidExpiry() {
        var s = PerfectSession()
        s.idle    = 100
        s.updated = Int(Date().timeIntervalSince1970) - 200 // expired 100s ago
        #expect(!s.isValid())
    }

    @Test func sessionIsValidFresh() {
        var s = PerfectSession()
        s.idle    = 86400
        s.updated = Int(Date().timeIntervalSince1970)
        #expect(s.isValid())
    }

    @Test func sessionIsValidIPLock() {
        var s = PerfectSession()
        s.idle      = 86400
        s.updated   = Int(Date().timeIntervalSince1970)
        s.ipaddress = "10.0.0.1"
        let prev = SessionConfig.IPAddressLock
        SessionConfig.IPAddressLock = true
        defer { SessionConfig.IPAddressLock = prev }
        #expect(s.isValid(ipaddress: "10.0.0.1"))
        #expect(!s.isValid(ipaddress: "10.0.0.2"))
    }

    @Test func sessionIsValidUALock() {
        var s = PerfectSession()
        s.idle      = 86400
        s.updated   = Int(Date().timeIntervalSince1970)
        s.useragent = "Safari/17"
        let prev = SessionConfig.userAgentLock
        SessionConfig.userAgentLock = true
        defer { SessionConfig.userAgentLock = prev }
        #expect(s.isValid(useragent: "Safari/17"))
        #expect(!s.isValid(useragent: "Chrome/120"))
    }

    // MARK: - MemorySessionDriver

    @Test func memoryCreate() async {
        let driver = MemorySessionDriver()
        let session = await driver.create(ipaddress: "1.2.3.4", useragent: "TestAgent")
        #expect(!session.token.isEmpty)
        #expect(session.ipaddress == "1.2.3.4")
        #expect(session.useragent == "TestAgent")
        #expect(session._state == "new")
        #expect(session.data["csrf"] as? String != nil)
    }

    @Test func memoryResume() async throws {
        let driver = MemorySessionDriver()
        let created = await driver.create()
        let resumed = try await driver.resume(token: created.token)
        #expect(resumed.token == created.token)
        #expect(resumed._state == "resume")
    }

    @Test func memoryResumeMissing() async {
        let driver = MemorySessionDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "nonexistent")
        }
    }

    @Test func memorySave() async throws {
        let driver = MemorySessionDriver()
        var session = await driver.create()
        session.userid = "user123"
        session.touch()
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "user123")
    }

    @Test func memoryDestroy() async {
        let driver = MemorySessionDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func memoryClean() async throws {
        let driver = MemorySessionDriver()
        var session = await driver.create()
        // expire: set updated far in the past so clean() will purge it
        session.idle    = 1
        session.updated = 0  // epoch — definitely expired
        await driver.save(session)
        await driver.clean()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    // MARK: - AuthFilter (uses local config to avoid parallel-test races on global state)

    @Test func authFilterInclusion() {
        var config = AuthenticationConfig()
        config.include("/admin")
        config.include("/profile")
        #expect(AuthFilter.shouldWeAccept("/admin",   using: config))
        #expect(AuthFilter.shouldWeAccept("/profile", using: config))
        #expect(!AuthFilter.shouldWeAccept("/public", using: config))
    }

    @Test func authFilterWildcard() {
        var config = AuthenticationConfig()
        config.include("/admin/*")
        #expect(AuthFilter.shouldWeAccept("/admin/users",    using: config))
        #expect(AuthFilter.shouldWeAccept("/admin/settings", using: config))
        #expect(!AuthFilter.shouldWeAccept("/public/page",   using: config))
    }

    @Test func authFilterExclusion() {
        var config = AuthenticationConfig()
        config.include("*")
        config.exclude("/healthcheck")
        #expect(AuthFilter.shouldWeAccept("/anything",    using: config))
        #expect(!AuthFilter.shouldWeAccept("/healthcheck", using: config))
    }

    // MARK: - CSRFSecurity

    @Test func csrfSecurityMatchingHosts() {
        #expect(CSRFSecurity.isValid(origin: "example.com", host: "example.com"))
    }

    @Test func csrfSecurityMismatch() {
        #expect(!CSRFSecurity.isValid(origin: "evil.com", host: "example.com"))
    }

    @Test func csrfSecurityEmptyOrigin() {
        #expect(!CSRFSecurity.isValid(origin: "", host: "example.com"))
    }

    @Test func csrfSecurityStripsScheme() {
        #expect(CSRFSecurity.isValid(origin: "https://example.com", host: "http://example.com"))
    }

    @Test func csrfSecurityAcceptableHostnames() {
        let prev = SessionConfig.CSRF.acceptableHostnames
        SessionConfig.CSRF.acceptableHostnames = ["trusted.com"]
        defer { SessionConfig.CSRF.acceptableHostnames = prev }
        #expect(CSRFSecurity.isValid(origin: "trusted.com", host: "other.com"))
        #expect(!CSRFSecurity.isValid(origin: "untrusted.com", host: "other.com"))
    }

    // MARK: - CookieSameSite

    @Test func cookieSameSiteRawValues() {
        #expect(CookieSameSite.strict.rawValue == "Strict")
        #expect(CookieSameSite.lax.rawValue    == "Lax")
        #expect(CookieSameSite.none.rawValue   == "None")
    }
}
