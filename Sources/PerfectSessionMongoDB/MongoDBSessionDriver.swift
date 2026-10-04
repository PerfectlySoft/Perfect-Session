import Foundation
import PerfectMongoDB
import PerfectSessionCore
import Logging

private let logger = Logger(label: "perfect.session.mongodb")

/// Connection settings used by `MongoDBSessionDriver()`.
public struct MongoDBSessionConnector: Sendable {
    nonisolated(unsafe) public static var uri: String        = "mongodb://localhost"
    nonisolated(unsafe) public static var database: String   = "perfect_sessions"
    nonisolated(unsafe) public static var collection: String = "sessions"
    private init() {}
}

/// Stores sessions as MongoDB documents, one per token:
///
///     { _id: <token>, userid, created, updated, idle, ipaddress, useragent,
///       data: { ... }, expiresAt: <Date> }
///
/// `data` is a real subdocument, not JSON text. Keys libmongoc won't store are escaped (see
/// `SessionDocument`). `setup()` adds a TTL index on `expiresAt` (`updated + idle`), so MongoDB
/// deletes expired sessions on its own; `clean()` still deletes them immediately for callers
/// that rely on it. Like the other drivers, `resume` returns expired sessions too: callers
/// check `PerfectSession.isValid()`.
///
/// `save` only updates an existing session, so a save racing a `destroy` (logout) can't bring
/// the session back. `setup()` also deletes documents left by the archived Perfect-Session-MongoDB
/// package (keyed by `token`, with no `expiresAt`): this driver can't resume them and the TTL
/// index never expires them.
///
/// All database work goes through a `MongoClientPool`, off Swift's cooperative thread pool.
public final class MongoDBSessionDriver: SessionDriver, Sendable {
    let pool: MongoClientPool
    let database: String
    let collection: String

    /// Uses `MongoDBSessionConnector`. Traps if its `uri` is not a valid connection string.
    public convenience init() {
        do {
            try self.init(uri: MongoDBSessionConnector.uri,
                          database: MongoDBSessionConnector.database,
                          collection: MongoDBSessionConnector.collection)
        } catch {
            fatalError("MongoDBSessionDriver: \(error)")
        }
    }

    /// Throws `MongoError` if **uri** is not a valid connection string.
    public convenience init(uri: String, database: String = "perfect_sessions", collection: String = "sessions") throws {
        self.init(pool: try MongoClientPool(validatingURI: uri), database: database, collection: collection)
    }

    /// Shares an application's existing pool.
    public init(pool: MongoClientPool, database: String = "perfect_sessions", collection: String = "sessions") {
        self.pool = pool
        self.database = database
        self.collection = collection
    }

    public func setup() async {
        do {
            try await withCollection { sessions in
                let keys = BSON()
                keys.append(key: "expiresAt", int: 1)
                let options = MongoIndexOptions(name: "expiresAt_ttl", expireAfterSeconds: 0)
                if case .error(_, _, let message) = sessions.createIndex(keys: keys, options: options) {
                    throw MongoError(domain: 0, code: 0, message: message)
                }
            }
        } catch {
            logger.error("session setup failed: \(error)")
        }
        await purgeLegacySessions()
    }

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = UUID().uuidString
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        let document = SessionDocument(session)
        do {
            try await withCollection { try $0.insert(document) }
        } catch {
            logger.error("session create failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let found: SessionDocument?
        do {
            found = try await withCollection { sessions in
                try sessions.findOne(SessionDocument.self, filter: Self.filter(token: token))
            }
        } catch {
            logger.error("session resume failed: \(error)", metadata: ["eventid": "\(token)"])
            throw InvalidSessionError()
        }
        guard var session = found?.session else {
            throw InvalidSessionError()
        }
        session._state = "resume"
        return session
    }

    public func save(_ session: PerfectSession) async {
        let document = SessionDocument(session)
        do {
            let matched = try await withCollection { sessions in
                try sessions.replaceOne(filter: Self.filter(token: document._id), with: document, upsert: false)
            }
            if matched == 0 {
                // Expected after a logout when middleware saves at the end of the request.
                logger.debug("session save matched no session (destroyed or expired); not recreated",
                             metadata: ["eventid": "\(session.token)"])
            }
        } catch {
            logger.error("session save failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
    }

    public func destroy(token: String) async {
        do {
            _ = try await withCollection { try $0.deleteOne(filter: Self.filter(token: token)) }
        } catch {
            logger.error("session destroy failed: \(error)", metadata: ["eventid": "\(token)"])
        }
    }

    public func clean() async {
        let now = Date()
        do {
            try await withCollection { sessions in
                let before = BSON()
                before.append(key: "$lt", dateTime: Self.millis(now))
                let filter = BSON()
                filter.append(key: "expiresAt", document: before)
                try sessions.deleteMany(filter: filter)
            }
        } catch {
            logger.error("session clean failed: \(error)")
        }
    }

    // MARK: - Private helpers

    /// Deletes documents written by the archived Perfect-Session-MongoDB: `{_id, token, userid,
    /// created, updated, idle, data, ipaddress, useragent}` with `data` as JSON text and no
    /// `expiresAt`. Documents this driver writes always have `expiresAt` and never a `token` field;
    /// the rest of the shape keeps unrelated documents that happen to have a `token` safe.
    private func purgeLegacySessions() async {
        let filter = #"""
            {"token": {"$type": "string"}, "data": {"$type": "string"}, "created": {"$exists": true},
             "updated": {"$exists": true}, "idle": {"$exists": true}, "expiresAt": {"$exists": false}}
            """#
        do {
            let deleted = try await withCollection { sessions in
                try sessions.deleteMany(filter: try BSON(json: filter))
            }
            if deleted > 0 {
                logger.notice("deleted \(deleted) legacy Perfect-Session-MongoDB session(s)")
            }
        } catch {
            logger.error("legacy session purge failed: \(error)")
        }
    }

    private func withCollection<T: Sendable>(_ body: @Sendable @escaping (MongoCollection) throws -> T) async throws -> T {
        let database = self.database
        let collection = self.collection
        return try await pool.withClient { client in
            try body(client.getCollection(databaseName: database, collectionName: collection))
        }
    }

    private static func filter(token: String) -> BSON {
        let filter = BSON()
        filter.append(key: "_id", string: token)
        return filter
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}

/// The stored form of a `PerfectSession`.
///
/// libmongoc rejects an empty key, and a key containing NUL would be cut short, so keys in
/// `data` (at any depth) are escaped: `%` → `%25`, NUL → `%00`, and the empty key → `%`.
/// Every other key is stored as is, so queries like `data.role` keep working.
struct SessionDocument: Codable, Sendable {
    var _id: String
    var userid: String
    var created: Int
    var updated: Int
    var idle: Int
    var ipaddress: String
    var useragent: String
    var data: JSONValue
    var expiresAt: Date

    init(_ session: PerfectSession) {
        _id       = session.token
        userid    = session.userid
        created   = session.created
        updated   = session.updated
        idle      = session.idle
        ipaddress = session.ipaddress
        useragent = session.useragent
        // Through JSON text, not [String: Any] casts: on Darwin a JSON true and 1 are both NSNumber.
        data      = ((try? JSONDecoder().decode(JSONValue.self, from: Data(session.tojson().utf8))) ?? .object([:]))
            .mappingKeys(Self.escape)
        expiresAt = Date(timeIntervalSince1970: TimeInterval(session.updated + session.idle))
    }

    var session: PerfectSession {
        var session = PerfectSession()
        session.token     = _id
        session.userid    = userid
        session.created   = created
        session.updated   = updated
        session.idle      = idle
        session.ipaddress = ipaddress
        session.useragent = useragent
        if let json = try? JSONEncoder().encode(data.mappingKeys(Self.unescape)) {
            session.fromjson(String(decoding: json, as: UTF8.self))
        }
        return session
    }

    static func escape(_ key: String) -> String {
        guard !key.isEmpty else {
            return "%"
        }
        guard key.utf8.contains(where: { $0 == 0x25 || $0 == 0 }) else {
            return key
        }
        var bytes: [UInt8] = []
        for byte in key.utf8 {
            switch byte {
            case 0x25: bytes += Array("%25".utf8)
            case 0:    bytes += Array("%00".utf8)
            default:   bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func unescape(_ key: String) -> String {
        guard key != "%" else {
            return ""
        }
        guard key.utf8.contains(0x25) else {
            return key
        }
        let utf8 = Array(key.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < utf8.count {
            let escape = utf8[index] == 0x25 && index + 2 < utf8.count ? (utf8[index + 1], utf8[index + 2]) : nil
            switch escape {
            case (0x32, 0x35)?: // %25
                bytes.append(0x25)
                index += 3
            case (0x30, 0x30)?: // %00
                bytes.append(0)
                index += 3
            default: // Not an escape this driver writes: keep it as is.
                bytes.append(utf8[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// A JSON value, so `PerfectSession.data` can be stored as a BSON subdocument.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Rewrites object keys at every depth.
    func mappingKeys(_ transform: (String) -> String) -> JSONValue {
        switch self {
        case .array(let values):
            return .array(values.map { $0.mappingKeys(transform) })
        case .object(let members):
            return .object(Dictionary(members.map { (transform($0.key), $0.value.mappingKeys(transform)) },
                                      uniquingKeysWith: { first, _ in first }))
        default:
            return self
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:              try container.encodeNil()
        case .bool(let value):   try container.encode(value)
        case .int(let value):    try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
