import Testing
import Foundation
@testable import PerfectSessionMongoDB
import PerfectSessionCore
import PerfectMongoDB

/// Needs a MongoDB server: MONGODB_TESTS=1 [MONGODB_URI=mongodb://host:27017] swift test
@Suite(.serialized) struct PerfectSessionMongoDBTests {

    static let mongoEnabled = ProcessInfo.processInfo.environment["MONGODB_TESTS"] == "1"
    static let uri = ProcessInfo.processInfo.environment["MONGODB_URI"] ?? "mongodb://localhost"

    func getDriver(collection: String = "sessions_test") throws -> MongoDBSessionDriver {
        try MongoDBSessionDriver(uri: Self.uri, database: "perfect_sessions_test", collection: collection)
    }

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

    @Test func emptyKeySavesAndResumes() async throws {
        guard Self.mongoEnabled else { return }
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
        guard Self.mongoEnabled else { return }
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
        guard Self.mongoEnabled else { return }
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
        guard Self.mongoEnabled else { return }
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
        guard Self.mongoEnabled else { return }
        let driver = try getDriver()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: "no-such-token")
        }
    }

    @Test func saveAndResume() async throws {
        guard Self.mongoEnabled else { return }
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

    @Test func destroyRemovesSession() async throws {
        guard Self.mongoEnabled else { return }
        let driver = try getDriver()
        let session = await driver.create()
        await driver.destroy(token: session.token)
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: session.token)
        }
    }

    @Test func dataIsStoredAsSubdocument() async throws {
        guard Self.mongoEnabled else { return }
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
        guard Self.mongoEnabled else { return }
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
        await driver.clean()
        await #expect(throws: InvalidSessionError.self) {
            _ = try await driver.resume(token: expired.token)
        }
        _ = try await driver.resume(token: live.token)
        await driver.destroy(token: live.token)
    }
}
