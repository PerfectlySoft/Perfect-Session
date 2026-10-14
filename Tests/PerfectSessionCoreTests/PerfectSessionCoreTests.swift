import Testing
import Foundation
@testable import PerfectSessionCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Whether the ThreadSanitizer runtime is loaded.
let underThreadSanitizer: Bool = {
    #if os(Linux)
    let defaultHandle: UnsafeMutableRawPointer? = nil          // RTLD_DEFAULT
    #else
    let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    #endif
    return dlsym(defaultHandle, "__tsan_init") != nil
}()

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
        s.data["ok"] = "kept"
        s.data["csrf"] = "csrf-token"
        switch kind {
        case "nan":      s.data["x"] = Double.nan
        case "infinity": s.data["x"] = Double.infinity
        case "date":     s.data["x"] = Date()
        case "url":      s.data["x"] = URL(string: "https://example.com")!
        case "intKey":   s.data["x"] = [1: "one"]
        default:         s.data["x"] = ["when": [Date()]]
        }
        // Only the bad key goes; the rest of the data and the CSRF token stay.
        var restored = PerfectSession()
        restored.fromjson(s.tojson())
        #expect(restored.data["ok"] as? String == "kept")
        #expect(restored.data["csrf"] as? String == "csrf-token")
        #expect(restored.data["x"] == nil)
    }

    /// A CSRF token JSON can't hold is replaced, never dropped.
    @Test func sessionToJsonReplacesBadCSRF() {
        var s = PerfectSession()
        s.data["csrf"] = Date()
        var restored = PerfectSession()
        restored.fromjson(s.tojson())
        #expect((restored.data["csrf"] as? String)?.count == 64)
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
        session.idle = -10   // save() renews `updated`, so expire it through idle
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
        #expect(s.isValid(ipaddress: "10.0.0.1", ipAddressLock: true))
        #expect(!s.isValid(ipaddress: "10.0.0.2", ipAddressLock: true))
        #expect(s.isValid(ipaddress: "10.0.0.2", ipAddressLock: false))
    }

    @Test func sessionIsValidUALock() {
        var s = PerfectSession()
        s.idle      = 86400
        s.updated   = Int(Date().timeIntervalSince1970)
        s.useragent = "Safari/17"
        #expect(s.isValid(useragent: "Safari/17", userAgentLock: true))
        #expect(!s.isValid(useragent: "Chrome/120", userAgentLock: true))
        #expect(s.isValid(useragent: "Chrome/120", userAgentLock: false))
    }

    // MARK: - Tokens

    /// logID is the first 12 hex digits of the token's SHA-256.
    @Test func logIDIsSHA256Prefix() {
        #expect(PerfectSession.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(PerfectSession.sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(PerfectSession.sha256Hex(String(repeating: "a", count: 1000)) ==
                "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
        #expect(PerfectSession.logID("abc") == "ba7816bf8f01")
    }

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
    /// (Skipped under ThreadSanitizer, whose runtime aborts a process with no descriptors left.)
    @Test(.disabled(if: underThreadSanitizer, "ThreadSanitizer needs file descriptors"))
    func tokensStayRandomWithoutFileDescriptors() async {
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

    /// Concurrent saves and resumes of one session: last writer wins, nothing is corrupted or lost.
    @Test func concurrentSaveAndResume() async throws {
        let driver = MemorySessionDriver()
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
        let driver = MemorySessionDriver()
        var session = await driver.create()
        session.userid = "signed-in"
        session.data["kept"] = "yes"
        session.data["when"] = Date()
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "signed-in")
        #expect(resumed.data["kept"] as? String == "yes")
        // The memory driver keeps values as they are, so "when" survives here.
        #expect(resumed.data["csrf"] as? String == session.data["csrf"] as? String)
        await driver.destroy(token: session.token)
    }

    /// A stored session without a CSRF token gets one when it's resumed.
    @Test func resumeRestoresMissingCSRF() async throws {
        let driver = MemorySessionDriver()
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
        let driver = MemorySessionDriver()
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
        let driver = MemorySessionDriver()
        var session = await driver.create()
        session.created -= 1000
        await driver.save(session)
        let fresh = await driver.regenerate(session)
        #expect(fresh.created == session.created)
        #expect(try await driver.resume(token: fresh.token).created == session.created)
        await driver.destroy(token: fresh.token)
    }

    @Test func memoryClean() async throws {
        let driver = MemorySessionDriver()
        var session = await driver.create()
        // expire: set updated far in the past so clean() will purge it
        session.idle    = -10   // save() renews `updated`, so expire it through idle
        await driver.save(session)
        await driver.clean()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    // MARK: - AuthFilter (uses local config to avoid parallel-test races on global state)

    func requiresAuth(_ path: String, _ config: AuthenticationConfig) -> Bool {
        AuthFilter.requiresAuthentication(path, using: config)
    }

    @Test func authFilterInclusion() {
        var config = AuthenticationConfig()
        config.include("/admin")
        config.include("/profile")
        #expect(requiresAuth("/admin", config))
        #expect(requiresAuth("/profile", config))
        #expect(!requiresAuth("/public", config))
    }

    @Test func authFilterWildcard() {
        var config = AuthenticationConfig()
        config.include("/admin/*")
        #expect(requiresAuth("/admin/users", config))
        #expect(requiresAuth("/admin/settings", config))
        #expect(requiresAuth("/admin", config))
        #expect(!requiresAuth("/public/page", config))
    }

    @Test func authFilterExclusion() {
        var config = AuthenticationConfig()
        config.include("*")
        config.exclude("/healthcheck")
        #expect(requiresAuth("/anything", config))
        #expect(!requiresAuth("/healthcheck", config))
    }

    /// Perfect-NIO 0.1.0 routes /ADMIN and /Admin/users to the /admin handlers, and the old
    /// string matching said they needed no authentication.
    @Test(arguments: ["/admin", "/Admin", "/ADMIN", "/admin/", "//admin", "/./admin", "/Admin/users",
                      "/ADMIN/USERS", "/admin/users/", "/admin//users", "/admin/./users",
                      "/%61dmin", "/admin;x=1", "/x/../admin", "/admin\\users", "admin"])
    func authFilterNormalizesPaths(_ path: String) {
        var config = AuthenticationConfig()
        config.include("/admin")
        #expect(requiresAuth(path, config), "\(path)")
    }

    /// A pattern covers its own path and everything below it, segment by segment.
    @Test func authFilterMatchesWholeSegments() {
        var config = AuthenticationConfig()
        config.include("/admin")
        #expect(!requiresAuth("/administrator", config))
        #expect(!requiresAuth("/adm", config))
        #expect(!requiresAuth("/", config))
        config = AuthenticationConfig()
        config.include("/api/*")
        config.exclude("/api/public")
        #expect(requiresAuth("/api/x", config))
        #expect(!requiresAuth("/api/public", config))
        #expect(!requiresAuth("/API/Public/docs", config))
        #expect(!requiresAuth("/apis", config))
    }

    /// `*` is only a wildcard as a whole final segment. An inclusion that uses it any other
    /// way ("*.json", "/admin*") requires authentication everywhere rather than silently
    /// protecting nothing; such an exclusion matches nothing.
    @Test func authFilterRejectsPartialWildcards() {
        var config = AuthenticationConfig()
        config.include("/admin*")
        #expect(requiresAuth("/administrator", config))
        #expect(requiresAuth("/public", config))
        config = AuthenticationConfig()
        config.include("*")
        config.exclude("*.json")
        #expect(requiresAuth("/x.json", config))
    }

    /// Case-folding can be turned off for servers that route case-sensitively.
    @Test func authFilterCaseSensitiveOption() {
        var config = AuthenticationConfig()
        config.include("/admin")
        config.caseInsensitive = false
        #expect(requiresAuth("/admin/x", config))
        #expect(!requiresAuth("/Admin", config))
    }

    /// With nothing protected, odd characters don't start requiring authentication.
    @Test func authFilterNoInclusionsNeverRequiresAuth() {
        let config = AuthenticationConfig()
        #expect(!requiresAuth("/caf%C3%A9", config))
        #expect(!requiresAuth("/../x", config))
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
        #expect(CSRFSecurity.isValid(origin: "trusted.com", host: "other.com", acceptableHostnames: ["trusted.com"]))
        #expect(!CSRFSecurity.isValid(origin: "untrusted.com", host: "other.com", acceptableHostnames: ["trusted.com"]))
    }

    @Test func csrfTokenMatches() {
        let token = PerfectSession.newToken()
        #expect(CSRFSecurity.tokenMatches(token, token))
        #expect(!CSRFSecurity.tokenMatches(token.uppercased(), token))
        #expect(!CSRFSecurity.tokenMatches(String(token.dropLast()), token))
        #expect(!CSRFSecurity.tokenMatches(token + "0", token))
        #expect(!CSRFSecurity.tokenMatches("", ""))
        #expect(!CSRFSecurity.tokenMatches("", token))
    }

    // MARK: - CORSSecurity

    /// A wildcard pattern used to accept any origin that matched its prefix OR its suffix, so
    /// "https://*.example.com" accepted every https origin.
    @Test func corsWildcardNeedsPrefixAndSuffix() {
        var config = SessionConfig.CORSconfig()
        config.enabled = true
        config.acceptableHostnames = ["https://*.example.com", "http://localhost:*"]
        #expect(CORSSecurity.isAcceptable(origin: "https://app.example.com", config: config))
        #expect(CORSSecurity.isAcceptable(origin: "https://A.Example.com", config: config))
        #expect(CORSSecurity.isAcceptable(origin: "http://localhost:8080", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "https://evil.com", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "https://example.com.evil.com", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "http://app.example.com", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "https://localhost:8080", config: config))

        config.acceptableHostnames = ["*.example.com"]
        #expect(CORSSecurity.isAcceptable(origin: "https://app.example.com", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "https://example.org", config: config))

        config.acceptableHostnames = ["https://Exact.example.com"]
        #expect(CORSSecurity.isAcceptable(origin: "https://exact.example.com", config: config))
        #expect(!CORSSecurity.isAcceptable(origin: "https://other.example.com", config: config))

        config.enabled = false
        #expect(!CORSSecurity.isAcceptable(origin: "https://exact.example.com", config: config))
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
        // Browsers match the prefixes ignoring case.
        withCookieConfig(name: "__HOST-sid", domain: "example.com") {
            #expect(SessionCookie.setCookie(token: "t") == nil)
        }
        withCookieConfig(name: "__host-sid") {
            #expect(SessionCookie.setCookie(token: "t") == "__host-sid=t; Path=/; HttpOnly; Secure; SameSite=Strict")
        }
        withCookieConfig(name: "__SECURE-sid") {
            #expect(SessionCookie.setCookie(token: "t") == "__SECURE-sid=t; Path=/; HttpOnly; Secure; SameSite=Strict")
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
