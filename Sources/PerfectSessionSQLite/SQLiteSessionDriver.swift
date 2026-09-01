import Foundation
import PerfectSQLite
import PerfectSessionCore
import Logging

private let logger = Logger(label: "perfect.session.sqlite")

public struct SQLiteSessionConnector: Sendable {
    nonisolated(unsafe) public static var databasePath: String = "./sessions.db"
    nonisolated(unsafe) public static var table: String        = "sessions"
    private init() {}
}

public final class SQLiteSessionDriver: SessionDriver, @unchecked Sendable {
    public init() {}

    public func setup() async {
        do {
            let db = try SQLite(SQLiteSessionConnector.databasePath)
            defer { db.close() }
            try db.execute(statement: """
                CREATE TABLE IF NOT EXISTS "\(SQLiteSessionConnector.table)" (
                    "token"     TEXT NOT NULL,
                    "userid"    TEXT,
                    "created"   INTEGER NOT NULL DEFAULT 0,
                    "updated"   INTEGER NOT NULL DEFAULT 0,
                    "idle"      INTEGER NOT NULL DEFAULT 0,
                    "data"      TEXT,
                    "ipaddress" TEXT,
                    "useragent" TEXT,
                    PRIMARY KEY ("token")
                )
                """)
        } catch {
            logger.error("session setup failed: \(error)")
        }
    }

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = UUID().uuidString
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        do {
            let db = try SQLite(SQLiteSessionConnector.databasePath)
            defer { db.close() }
            try db.execute(
                statement: "INSERT INTO \"\(SQLiteSessionConnector.table)\" (token,userid,created,updated,idle,data,ipaddress,useragent) VALUES(?,?,?,?,?,?,?,?)",
                doBindings: { stmt in
                    try stmt.bind(position: 1, session.token)
                    try stmt.bind(position: 2, session.userid)
                    try stmt.bind(position: 3, session.created)
                    try stmt.bind(position: 4, session.updated)
                    try stmt.bind(position: 5, session.idle)
                    try stmt.bind(position: 6, session.tojson())
                    try stmt.bind(position: 7, session.ipaddress)
                    try stmt.bind(position: 8, session.useragent)
                }
            )
        } catch {
            logger.error("session create failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        var found: PerfectSession? = nil
        let db = try SQLite(SQLiteSessionConnector.databasePath)
        defer { db.close() }
        try db.forEachRow(
            statement: "SELECT token,userid,created,updated,idle,data,ipaddress,useragent FROM \"\(SQLiteSessionConnector.table)\" WHERE token = ?",
            doBindings: { stmt in try stmt.bind(position: 1, token) },
            handleRow: { stmt, _ in
                var s = PerfectSession()
                s.token     = stmt.columnText(position: 0)
                s.userid    = stmt.columnText(position: 1)
                s.created   = stmt.columnInt(position: 2)
                s.updated   = stmt.columnInt(position: 3)
                s.idle      = stmt.columnInt(position: 4)
                s.fromjson(stmt.columnText(position: 5))
                s.ipaddress = stmt.columnText(position: 6)
                s.useragent = stmt.columnText(position: 7)
                found = s
            }
        )
        guard var s = found else { throw InvalidSessionError() }
        s._state = "resume"
        return s
    }

    public func save(_ session: PerfectSession) async {
        do {
            let db = try SQLite(SQLiteSessionConnector.databasePath)
            defer { db.close() }
            try db.execute(
                statement: "UPDATE \"\(SQLiteSessionConnector.table)\" SET userid=?,updated=?,idle=?,data=?,ipaddress=?,useragent=? WHERE token=?",
                doBindings: { stmt in
                    try stmt.bind(position: 1, session.userid)
                    try stmt.bind(position: 2, session.updated)
                    try stmt.bind(position: 3, session.idle)
                    try stmt.bind(position: 4, session.tojson())
                    try stmt.bind(position: 5, session.ipaddress)
                    try stmt.bind(position: 6, session.useragent)
                    try stmt.bind(position: 7, session.token)
                }
            )
        } catch {
            logger.error("session save failed: \(error)", metadata: ["eventid": "\(session.token)"])
        }
    }

    public func destroy(token: String) async {
        do {
            let db = try SQLite(SQLiteSessionConnector.databasePath)
            defer { db.close() }
            try db.execute(
                statement: "DELETE FROM \"\(SQLiteSessionConnector.table)\" WHERE token=?",
                doBindings: { stmt in try stmt.bind(position: 1, token) }
            )
        } catch {
            logger.error("session destroy failed: \(error)", metadata: ["eventid": "\(token)"])
        }
    }

    public func clean() async {
        do {
            let db = try SQLite(SQLiteSessionConnector.databasePath)
            defer { db.close() }
            let now = Int(Date().timeIntervalSince1970)
            try db.execute(
                statement: "DELETE FROM \"\(SQLiteSessionConnector.table)\" WHERE updated + idle < ?",
                doBindings: { stmt in try stmt.bind(position: 1, now) }
            )
        } catch {
            logger.error("session clean failed: \(error)")
        }
    }
}
