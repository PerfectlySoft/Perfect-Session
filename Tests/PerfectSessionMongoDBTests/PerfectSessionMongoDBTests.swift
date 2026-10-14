import Testing
import Foundation
@testable import PerfectSessionMongoDB
import PerfectSessionCore
import PerfectMongoDB

/// SessionDocument encoding; no server needed.
@Suite struct MongoDBSessionDocumentTests {

    @Test func documentRoundTripKeepsDataTypes() throws {
        var session = PerfectSession()
        session.token = "t1"
        session.data = ["flag": true, "count": 1, "ratio": 0.5, "name": "x",
                        "nested": ["list": [1, 2, 3]], "nothing": NSNull()]
        let document = SessionDocument(session)
        #expect(document.data == .object([
            "flag": .bool(true), "count": .int(1), "ratio": .double(0.5), "name": .string("x"),
            "nested": .object(["list": .array([.int(1), .int(2), .int(3)])]), "nothing": .null,
        ]))
        #expect(document.expiresAt == Date(timeIntervalSince1970: TimeInterval(session.updated + session.idle)))

        let stored = try BSONDecoder().decode(SessionDocument.self, from: try BSONEncoder().encode(document))
        let restored = stored.session
        #expect(restored.token == "t1")
        #expect(restored.data["flag"] as? Bool == true)
        #expect(restored.data["count"] as? Int == 1)
        #expect(restored.data["name"] as? String == "x")
    }

    /// `updated + idle` trapped on overflow when building the document, and a far-future
    /// `expiresAt` trapped in the BSON encoder.
    @Test(arguments: [Int.max, Int.max / 2, 1 << 50, Int.min, -(1 << 50)])
    func hugeIdleDoesNotTrap(_ idle: Int) throws {
        var session = PerfectSession()
        session.idle = idle
        let document = SessionDocument(session)
        let seconds = document.expiresAt.timeIntervalSince1970
        #expect(seconds <= 253_402_300_799 && seconds >= -62_135_596_800)
        _ = try BSONEncoder().encode(document)
    }

    @Test func keysBSONCantHoldAreEscapedAndRestored() throws {
        let awkward = ["", "%", "%%", "50%", "%25", "%00", "a%b", "nul\u{0}x", "\u{0}", "plain", "a.b", "$x"]
        for key in awkward {
            #expect(SessionDocument.unescape(SessionDocument.escape(key)) == key, "\(key.debugDescription)")
            let escaped = SessionDocument.escape(key)
            #expect(!escaped.isEmpty && !escaped.utf8.contains(0), "\(key.debugDescription)")
        }
        #expect(SessionDocument.escape("plain") == "plain")
        #expect(SessionDocument.escape("a.b") == "a.b")

        var session = PerfectSession()
        session.token = "t2"
        var data: [String: Any] = ["nested": ["": 2, "in\u{0}ner": ["%": 3]], "list": [["": 4]]]
        for (index, key) in awkward.enumerated() {
            data[key] = index
        }
        session.data = data
        let document = SessionDocument(session)
        guard case .object(let stored) = document.data else {
            Issue.record("data is not an object")
            return
        }
        #expect(stored["%"] == .int(0))
        #expect(stored[""] == nil)

        let restored = try BSONDecoder().decode(SessionDocument.self, from: try BSONEncoder().encode(document)).session
        for (index, key) in awkward.enumerated() {
            #expect(restored.data[key] as? Int == index, "\(key.debugDescription)")
        }
        let nested = restored.data["nested"] as? [String: Any]
        #expect(nested?[""] as? Int == 2)
        #expect((nested?["in\u{0}ner"] as? [String: Any])?["%"] as? Int == 3)
        #expect(((restored.data["list"] as? [Any])?.first as? [String: Any])?[""] as? Int == 4)
    }
}

/// Live-test settings, outside the suite so its traits can refer to them.
enum MongoDBLive {
    static let mongoEnabled = ProcessInfo.processInfo.environment["MONGODB_TESTS"] == "1"
    static let uri = ProcessInfo.processInfo.environment["MONGODB_URI"] ?? "mongodb://localhost"
}

/// Needs a MongoDB server: MONGODB_TESTS=1 [MONGODB_URI=mongodb://host:27017] swift test
@Suite(.serialized, .enabled(if: MongoDBLive.mongoEnabled, "set MONGODB_TESTS=1 to run against a server")) struct PerfectSessionMongoDBTests {

    func getDriver(collection: String = "sessions_test") throws -> MongoDBSessionDriver {
        try MongoDBSessionDriver(uri: MongoDBLive.uri, database: "perfect_sessions_test", collection: collection)
    }

    @Test func emptyKeySavesAndResumes() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        session.data[""] = "empty"
        session.data["visits"] = 2
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.data[""] as? String == "empty")
        #expect(resumed.data["visits"] as? Int == 2)
        await driver.destroy(token: session.token)
    }

    @Test func saveAfterDestroyDoesNotResurrect() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        session.userid = "logged-out"
        await driver.destroy(token: session.token)
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func setupPurgesLegacySessionsOnly() async throws {
        let driver = try getDriver(collection: "sessions_legacy_test")
        func insertLegacy(_ token: String) async throws {
            // The shape Perfect-Session-MongoDB wrote: its own _id, the token in a field, data as JSON text.
            try await driver.pool.withClient { client in
                let document = try BSON(json: """
                    {"_id": "\(UUID().uuidString)", "token": "\(token)", "userid": "", "created": 0, "updated": 0,
                     "idle": 86400, "data": "{}", "ipaddress": "", "useragent": ""}
                    """)
                let collection = client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_legacy_test")
                if case .error(_, _, let message) = collection.insert(document: document) {
                    throw MongoError(domain: 0, code: 0, message: message)
                }
            }
        }
        func count(_ json: String) async throws -> Int {
            try await driver.pool.withClient { client in
                try client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_legacy_test")
                    .countDocuments(filter: try BSON(json: json))
            }
        }
        try await driver.pool.withClient { client in
            _ = client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_legacy_test").drop()
        }
        try await insertLegacy("legacy-1")
        let current = await driver.create()
        try await driver.pool.withClient { client in
            // Not legacy sessions, though some have a token field: left alone.
            let collection = client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_legacy_test")
            for json in [#"{"_id": "unrelated", "note": "keep"}"#,
                         #"{"_id": "api-user", "email": "a@example.com", "token": "api-key-123"}"#,
                         #"{"_id": "reset", "token": null, "data": "{}", "created": 0, "updated": 0, "idle": 1}"#] {
                _ = collection.insert(document: try BSON(json: json))
            }
        }

        await driver.setup()
        #expect(try await count(#"{"token": {"$regex": "^legacy-"}}"#) == 0)
        #expect(try await count(#"{"_id": {"$in": ["unrelated", "api-user", "reset"]}}"#) == 3)
        _ = try await driver.resume(token: current.token)

        // clean() only expires sessions; the purge is a setup() step.
        try await insertLegacy("legacy-2")
        await driver.clean()
        #expect(try await count(#"{"token": "legacy-2"}"#) == 1)
        _ = try await driver.resume(token: current.token)
        await driver.destroy(token: current.token)
    }

    @Test func createAndResume() async throws {
        let driver = try getDriver()
        let session = await driver.create(ipaddress: "10.0.0.1", useragent: "MongoTest/1.0")
        #expect(!session.token.isEmpty)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.token == session.token)
        #expect(resumed.ipaddress == "10.0.0.1")
        #expect(resumed.useragent == "MongoTest/1.0")
        #expect(resumed._state == "resume")
        #expect(resumed.data["csrf"] as? String == session.data["csrf"] as? String)
        await driver.destroy(token: session.token)
    }

    @Test func resumeMissing() async throws {
        let driver = try getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        session.userid = "mongo-user-1"
        session.data["flag"] = true
        session.data["visits"] = 3
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect(resumed.userid == "mongo-user-1")
        #expect(resumed.data["flag"] as? Bool == true)
        #expect(resumed.data["visits"] as? Int == 3)
        await driver.destroy(token: session.token)
    }

    /// resume() used to return an expired session (until clean() ran), leaving the check to
    /// the caller.
    @Test func resumeRejectsExpired() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        session.idle    = 1
        session.updated = Int(Date().timeIntervalSince1970) - 10
        await driver.save(session)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
        await driver.destroy(token: session.token)
    }

    @Test func destroyRemovesSession() async throws {
        let driver = try getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func dataIsStoredAsSubdocument() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        session.data["role"] = "admin"
        await driver.save(session)
        let token = session.token
        let matches = try await driver.pool.withClient { client in
            try client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_test")
                .countDocuments(filter: try BSON(json: #"{"_id": "\#(token)", "data.role": "admin"}"#))
        }
        #expect(matches == 1)
        await driver.destroy(token: token)
    }

    @Test func setupCreatesTTLIndexAndCleanRemovesExpired() async throws {
        let driver = try getDriver(collection: "sessions_ttl_test")
        try await driver.pool.withClient { client in
            _ = client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_ttl_test").drop()
        }
        await driver.setup()
        let hasTTL = try await driver.pool.withClient { client in
            let command = try BSON(json: #"{"listIndexes": "sessions_ttl_test"}"#)
            let collection = client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_ttl_test")
            guard let cursor = collection.command(command: command) else { return false }
            return cursor.contains { $0.asString.contains("\"expireAfterSeconds\" : 0") }
        }
        #expect(hasTTL)

        var expired = await driver.create()
        expired.updated = Int(Date().timeIntervalSince1970) - 10
        expired.idle = 1
        await driver.save(expired)
        let live = await driver.create()
        // Counted directly: resume() refuses an expired session whether or not clean() deleted it.
        let token = expired.token
        func stored() async throws -> Int {
            try await driver.pool.withClient { client in
                try client.getCollection(databaseName: "perfect_sessions_test", collectionName: "sessions_ttl_test")
                    .countDocuments(filter: try BSON(json: #"{"_id": "\#(token)"}"#))
            }
        }
        #expect(try await stored() == 1)
        await driver.clean()
        #expect(try await stored() == 0)
        _ = try await driver.resume(token: live.token)
        await driver.destroy(token: live.token)
    }

    /// Concurrent saves and resumes of one session: last writer wins, nothing is corrupted or lost.
    @Test func concurrentSaveAndResume() async throws {
        let driver = try getDriver()
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
        let driver = try getDriver()
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
        let driver = try getDriver()
        var session = await driver.create()
        session.data.removeValue(forKey: "csrf")
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        #expect((resumed.data["csrf"] as? String)?.isEmpty == false)
        await driver.destroy(token: session.token)
    }

    @Test func regenerateMovesSessionToNewToken() async throws {
        let driver = try getDriver()
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

    /// Keys MongoDB treats specially in queries and updates are stored as data, at any depth.
    @Test func operatorAndDottedKeysRoundTrip() async throws {
        let driver = try getDriver()
        var session = await driver.create()
        let keys = ["$where", "$set", "$", "a.b", ".", "$x.y", "_id", "expiresAt"]
        for key in keys { session.data[key] = key }
        session.data["nested"] = ["$gt": 1, "c.d": ["$ne": "x"]]
        await driver.save(session)
        let resumed = try await driver.resume(token: session.token)
        for key in keys { #expect(resumed.data[key] as? String == key, "\(key)") }
        let nested = resumed.data["nested"] as? [String: Any]
        #expect(nested?["$gt"] as? Int == 1)
        #expect((nested?["c.d"] as? [String: Any])?["$ne"] as? String == "x")
        await driver.destroy(token: session.token)
    }

    /// The token is matched as a string, so one that looks like an operator matches nothing.
    @Test(arguments: [#"{"$ne": ""}"#, "$ne", #"{"$gt": ""}"#, ".*", "\u{0}"])
    func operatorLikeTokensMatchNothing(_ token: String) async throws {
        let driver = try getDriver()
        let other = await driver.create()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: token)
        }
        await driver.destroy(token: token)
        _ = try await driver.resume(token: other.token)
        await driver.destroy(token: other.token)
    }

    /// Fails, rather than letting the other tests pass vacuously, when the server can't be reached.
    @Test func serverIsReachable() async throws {
        let driver = try getDriver()
        let reachable = try await driver.pool.withClient { client in
            if case .replyDoc = client.serverStatus() { return true }
            return false
        }
        #expect(reachable, "can't reach MongoDB at \(MongoDBLive.uri)")
    }
}

/// CI sets SESSION_REQUIRE_LIVE=1, so a job that forgets MONGODB_TESTS fails rather than passing with
/// the live suite skipped.
@Test func mongoDBLiveTestsRunWhenRequired() {
    let required = ProcessInfo.processInfo.environment["SESSION_REQUIRE_LIVE"] == "1"
    #expect(!required || MongoDBLive.mongoEnabled, "SESSION_REQUIRE_LIVE=1 but MONGODB_TESTS is not 1")
}
