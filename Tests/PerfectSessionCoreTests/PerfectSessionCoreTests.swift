import Testing
import Foundation
@testable import PerfectSessionCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

    /// JSONSerialization raises an Objective-C exception (on Darwin), which Swift can't catch,
    /// for values JSON can't hold; tojson() used to crash the process on them.
    @Test(arguments: ["nan", "infinity", "date", "url", "intKey", "nestedDate"])
    func sessionToJsonNonJSONValueDoesNotCrash(_ kind: String) {
        var s = PerfectSession()
        s.data["ok"] = "kept out"
        switch kind {
        case "nan":      s.data["x"] = Double.nan
        case "infinity": s.data["x"] = Double.infinity
        case "date":     s.data["x"] = Date()
        case "url":      s.data["x"] = URL(string: "https://example.com")!
        case "intKey":   s.data["x"] = [1: "one"]
        default:         s.data["x"] = ["when": [Date()]]
        }
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

    /// `updated + idle` trapped on overflow, so an idle of Int.max ("never expire") crashed
    /// isValid() and MemorySessionDriver.clean().
    @Test func hugeIdleDoesNotTrap() async throws {
        var s = PerfectSession()
        s.idle = Int.max
        #expect(s.isValid())
        #expect(s.expires == Int.max)
        s.idle = Int.min
        #expect(!s.isValid())

        let driver = MemorySessionDriver()
        var stored = await driver.create()
        stored.idle = Int.max
        await driver.save(stored)
        await driver.clean()
        _ = try await driver.resume(token: stored.token)
    }

    @Test func absoluteTimeout() {
        var s = PerfectSession()
        let now = Int(Date().timeIntervalSince1970)
        s.created = now - 100
        s.updated = now
        s.idle    = 3600
        #expect(!s.isExpired(at: now, absoluteTimeout: 0))
        #expect(!s.isExpired(at: now, absoluteTimeout: 101))
        #expect(s.isExpired(at: now, absoluteTimeout: 100))
        #expect(!s.isExpired(at: now, absoluteTimeout: Int.max))
        #expect(s.isExpired(at: now + 3600, absoluteTimeout: 0))
    }

    /// resume() used to return an expired session, leaving the check to the caller.
    @Test func memoryResumeRejectsExpired() async {
        let driver = MemorySessionDriver()
        var session = await driver.create()
        session.idle    = 1
        session.updated = Int(Date().timeIntervalSince1970) - 10
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
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

    // MARK: - Tokens

    @Test func tokensAre256BitHex() async {
        let driver = MemorySessionDriver()
        var seen = Set<String>()
        for _ in 0..<500 {
            let session = await driver.create()
            for token in [session.token, session.data["csrf"] as? String ?? ""] {
                #expect(token.count == 64)
                #expect(token.allSatisfy { "0123456789abcdef".contains($0) })
                seen.insert(token)
            }
        }
        #expect(seen.count == 1000)
    }

    /// On Linux, Foundation's UUID() reads /dev/urandom and ignores a failed open(), so with no
    /// file descriptor left every UUID was 00000000-0000-4000-8000-000000000000: every new
    /// session got the same token. Runs in a child process, which it starves of descriptors.
    @Test func tokensStayRandomWithoutFileDescriptors() async {
        await #expect(processExitsWith: .success) {
            #if os(Linux)
            let resource = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
            #else
            let resource = RLIMIT_NOFILE
            #endif
            var limit = rlimit()
            getrlimit(resource, &limit)
            limit.rlim_cur = 64
            setrlimit(resource, &limit)
            while open("/dev/null", O_RDONLY) >= 0 {}
            let driver = MemorySessionDriver()
            let first = await driver.create(), second = await driver.create()
            let distinct = first.token != second.token
                && first.data["csrf"] as? String != second.data["csrf"] as? String
            exit(distinct ? EXIT_SUCCESS : EXIT_FAILURE)
        }
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

    /// save() used to insert, so a save racing a logout brought the session back, and saving a
    /// session built around a client-chosen token stored it (session fixation).
    @Test func memorySaveOnlyUpdatesStoredSessions() async {
        let driver = MemorySessionDriver()
        var session = await driver.create()
        session.userid = "logged-out"
        await driver.destroy(token: session.token)
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }

        var planted = PerfectSession()
        planted.token = "attacker-chosen"
        await driver.save(planted)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "attacker-chosen")
        }
    }

    /// There was no way to move a session to a new token, so a token fixed before sign-in
    /// stayed valid after it.
    @Test func memoryRegenerate() async throws {
        let driver = MemorySessionDriver()
        var session = await driver.create(ipaddress: "10.0.0.9", useragent: "UA")
        session.userid = "alice"
        session.data["cart"] = 3
        await driver.save(session)
        let fresh = await driver.regenerate(session)
        #expect(fresh.token != session.token)
        #expect(fresh.data["csrf"] as? String != session.data["csrf"] as? String)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
        let resumed = try await driver.resume(token: fresh.token)
        #expect(resumed.userid == "alice")
        #expect(resumed.data["cart"] as? Int == 3)
        #expect(resumed.data["csrf"] as? String == fresh.data["csrf"] as? String)
        #expect(resumed.ipaddress == "10.0.0.9")
        #expect(resumed.useragent == "UA")
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

    // MARK: - CORSSecurity

    /// A wildcard pattern used to accept any origin that matched its prefix OR its suffix, so
    /// "https://*.example.com" accepted every https origin.
    @Test func corsWildcardNeedsPrefixAndSuffix() {
        let prev = SessionConfig.CORS
        defer { SessionConfig.CORS = prev }
        SessionConfig.CORS.enabled = true
        SessionConfig.CORS.acceptableHostnames = ["https://*.example.com", "http://localhost:*"]
        #expect(CORSSecurity.isAcceptable(origin: "https://app.example.com"))
        #expect(CORSSecurity.isAcceptable(origin: "https://A.Example.com"))
        #expect(CORSSecurity.isAcceptable(origin: "http://localhost:8080"))
        #expect(!CORSSecurity.isAcceptable(origin: "https://evil.com"))
        #expect(!CORSSecurity.isAcceptable(origin: "https://example.com.evil.com"))
        #expect(!CORSSecurity.isAcceptable(origin: "http://app.example.com"))
        #expect(!CORSSecurity.isAcceptable(origin: "https://localhost:8080"))

        SessionConfig.CORS.acceptableHostnames = ["*.example.com"]
        #expect(CORSSecurity.isAcceptable(origin: "https://app.example.com"))
        #expect(!CORSSecurity.isAcceptable(origin: "https://example.org"))

        SessionConfig.CORS.acceptableHostnames = ["https://Exact.example.com"]
        #expect(CORSSecurity.isAcceptable(origin: "https://exact.example.com"))
        #expect(!CORSSecurity.isAcceptable(origin: "https://other.example.com"))
    }

    // MARK: - CookieSameSite

    @Test func cookieSameSiteRawValues() {
        #expect(CookieSameSite.strict.rawValue == "Strict")
        #expect(CookieSameSite.lax.rawValue    == "Lax")
        #expect(CookieSameSite.none.rawValue   == "None")
    }
}

/// Serialized because each test changes SessionConfig's cookie settings, which no other test reads.
@Suite(.serialized) struct SessionCookieTests {
    func withCookieConfig(name: String = "PerfectSession", domain: String = "", path: String = "/",
                          secure: Bool = false, httpOnly: Bool = true, sameSite: CookieSameSite = .strict,
                          _ body: () -> Void) {
        let saved = (SessionConfig.name, SessionConfig.cookieDomain, SessionConfig.cookiePath,
                     SessionConfig.cookieSecure, SessionConfig.cookieHTTPOnly, SessionConfig.cookieSameSite)
        defer {
            (SessionConfig.name, SessionConfig.cookieDomain, SessionConfig.cookiePath,
             SessionConfig.cookieSecure, SessionConfig.cookieHTTPOnly, SessionConfig.cookieSameSite) = saved
        }
        (SessionConfig.name, SessionConfig.cookieDomain, SessionConfig.cookiePath,
         SessionConfig.cookieSecure, SessionConfig.cookieHTTPOnly, SessionConfig.cookieSameSite) =
            (name, domain, path, secure, httpOnly, sameSite)
        body()
    }

    @Test func defaults() {
        withCookieConfig {
            #expect(SessionCookie.setCookie(token: "abc123") == "PerfectSession=abc123; Path=/; HttpOnly; SameSite=Strict")
            #expect(SessionCookie.expiredCookie() == "PerfectSession=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict")
        }
    }

    @Test func allAttributes() {
        withCookieConfig(domain: "example.com", path: "/app", secure: true, httpOnly: false, sameSite: .lax) {
            #expect(SessionCookie.setCookie(token: "t") == "PerfectSession=t; Path=/app; Domain=example.com; Secure; SameSite=Lax")
        }
    }

    @Test func sameSiteNoneAndPrefixesForceSecure() {
        withCookieConfig(sameSite: .none) {
            #expect(SessionCookie.setCookie(token: "t") == "PerfectSession=t; Path=/; HttpOnly; Secure; SameSite=None")
        }
        withCookieConfig(name: "__Host-sid") {
            #expect(SessionCookie.setCookie(token: "t") == "__Host-sid=t; Path=/; HttpOnly; Secure; SameSite=Strict")
        }
        withCookieConfig(name: "__Host-sid", domain: "example.com") {
            #expect(SessionCookie.setCookie(token: "t") == nil)
        }
        withCookieConfig(name: "__Host-sid", path: "/app") {
            #expect(SessionCookie.setCookie(token: "t") == nil)
        }
    }

    /// Settings or a token containing ";" or CR/LF would otherwise add attributes or headers.
    @Test func refusesValuesThatWouldInjectAttributes() {
        withCookieConfig {
            for token in ["a;Domain=evil.com", "a\r\nSet-Cookie: x=1", "a b", "a,b", "\"a\"", "é"] {
                #expect(SessionCookie.setCookie(token: token) == nil, "\(token.debugDescription)")
            }
        }
        withCookieConfig(name: "sid;Secure") { #expect(SessionCookie.setCookie(token: "t") == nil) }
        withCookieConfig(name: "") { #expect(SessionCookie.setCookie(token: "t") == nil) }
        withCookieConfig(domain: "example.com; SameSite=None") { #expect(SessionCookie.setCookie(token: "t") == nil) }
        withCookieConfig(path: "/;HttpOnly") { #expect(SessionCookie.setCookie(token: "t") == nil) }
        withCookieConfig(path: "/a\nb") { #expect(SessionCookie.setCookie(token: "t") == nil) }
        withCookieConfig {
            #expect(SessionCookie.setCookie(token: PerfectSession.newToken()) != nil)
        }
    }
}
