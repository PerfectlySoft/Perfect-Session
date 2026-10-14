import Foundation
import PerfectMySQL
import PerfectSessionCore

public struct MySQLSessionConnector: Sendable {
    nonisolated(unsafe) public static var host: String     = "localhost"
    nonisolated(unsafe) public static var socket: String   = ""
    nonisolated(unsafe) public static var username: String = ""
    nonisolated(unsafe) public static var password: String = ""
    nonisolated(unsafe) public static var database: String = "perfect_sessions"
    nonisolated(unsafe) public static var table: String    = "sessions"
    nonisolated(unsafe) public static var port: Int        = 3306
    private init() {}
}

public final class MySQLSessionDriver: SessionDriver, @unchecked Sendable {
    public init() {}

    public func setup() async {
        let sql = """
            CREATE TABLE IF NOT EXISTS `\(MySQLSessionConnector.table)` (
                `token`     varchar(255) NOT NULL,
                `userid`    varchar(255),
                `created`   bigint NOT NULL DEFAULT 0,
                `updated`   bigint NOT NULL DEFAULT 0,
                `idle`      bigint NOT NULL DEFAULT 0,
                `data`      text,
                `ipaddress` varchar(255),
                `useragent` text,
                PRIMARY KEY (`token`)
            )
            """
        exec(sql, params: [])
    }

    public func create(ipaddress: String = "", useragent: String = "") async -> PerfectSession {
        var session = PerfectSession()
        session.token     = UUID().uuidString
        session.ipaddress = ipaddress
        session.useragent = useragent
        session._state    = "new"
        session.setCSRF()
        exec(
            "INSERT INTO `\(MySQLSessionConnector.table)` (token,userid,created,updated,idle,data,ipaddress,useragent) VALUES(?,?,?,?,?,?,?,?)",
            params: [session.token, session.userid, session.created, session.updated,
                     session.idle, session.tojson(), session.ipaddress, session.useragent]
        )
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let db = connect()
        let stmt = MySQLStmt(db)
        // MySQLStmt keeps only a raw pointer to its connection, so keep `db` alive until the statement is done.
        defer { withExtendedLifetime((stmt, db)) {} }
        _ = stmt.prepare(statement: "SELECT token,userid,created,updated,idle,data,ipaddress,useragent FROM `\(MySQLSessionConnector.table)` WHERE token = ?")
        stmt.bindParam(token)
        _ = stmt.execute()
        let result = stmt.results()
        var found: PerfectSession? = nil
        _ = result.forEachRow { row in
            var s = PerfectSession()
            s.token     = row[0] as? String ?? ""
            s.userid    = row[1] as? String ?? ""
            s.created   = Self.int(row[2])
            s.updated   = Self.int(row[3])
            s.idle      = Self.int(row[4])
            if let d = row[5] as? String { s.fromjson(d) }
            s.ipaddress = row[6] as? String ?? ""
            s.useragent = row[7] as? String ?? ""
            found = s
        }
        guard var s = found else { throw InvalidSessionError() }
        s._state = "resume"
        return s
    }

    public func save(_ session: PerfectSession) async {
        exec(
            "UPDATE `\(MySQLSessionConnector.table)` SET userid=?,updated=?,idle=?,data=? WHERE token=?",
            params: [session.userid, session.updated, session.idle, session.tojson(), session.token]
        )
    }

    public func destroy(token: String) async {
        exec("DELETE FROM `\(MySQLSessionConnector.table)` WHERE token=?", params: [token])
    }

    public func clean() async {
        exec(
            // DECIMAL arithmetic: a BIGINT sum overflows (an error) for an idle near Int.max.
            "DELETE FROM `\(MySQLSessionConnector.table)` WHERE CAST(updated AS DECIMAL(30,0)) + idle < ?",
            params: [Int(Date().timeIntervalSince1970)]
        )
    }

    // MARK: - Private helpers

    /// An integer column: Int64 from the BIGINT columns `setup()` creates, Int32 from the INT
    /// columns of tables created before 4.0.
    private static func int(_ value: Any?) -> Int {
        switch value {
        case let v as Int64:  return Int(v)
        case let v as Int32:  return Int(v)
        case let v as Int:    return v
        case let v as UInt64: return Int(exactly: v) ?? Int.max
        case let v as UInt32: return Int(v)
        case let v as String: return Int(v) ?? 0
        default:              return 0
        }
    }

    private func connect() -> MySQL {
        let db = MySQL()
        if MySQLSessionConnector.socket.isEmpty {
            _ = db.connect(
                host: MySQLSessionConnector.host,
                user: MySQLSessionConnector.username,
                password: MySQLSessionConnector.password,
                db: MySQLSessionConnector.database,
                port: UInt32(MySQLSessionConnector.port)
            )
        } else {
            _ = db.connect(
                user: MySQLSessionConnector.username,
                password: MySQLSessionConnector.password,
                db: MySQLSessionConnector.database,
                socket: MySQLSessionConnector.socket
            )
        }
        return db
    }

    private func exec(_ statement: String, params: [Any]) {
        let db = connect()
        let stmt = MySQLStmt(db)
        // MySQLStmt keeps only a raw pointer to its connection, so keep `db` alive until the statement is done.
        defer { withExtendedLifetime((stmt, db)) {} }
        _ = stmt.prepare(statement: statement)
        for p in params { stmt.bindParam("\(p)") }
        _ = stmt.execute()
        _ = stmt.results()
    }
}
