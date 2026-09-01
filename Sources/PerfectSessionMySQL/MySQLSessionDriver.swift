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
                `created`   int NOT NULL DEFAULT 0,
                `updated`   int NOT NULL DEFAULT 0,
                `idle`      int NOT NULL DEFAULT 0,
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
        defer { stmt.close(); db.close() }
        _ = stmt.prepare(statement: "SELECT token,userid,created,updated,idle,data,ipaddress,useragent FROM `\(MySQLSessionConnector.table)` WHERE token = ?")
        stmt.bindParam(token)
        _ = stmt.execute()
        let result = stmt.results()
        var found: PerfectSession? = nil
        _ = result.forEachRow { row in
            var s = PerfectSession()
            s.token     = row[0] as? String ?? ""
            s.userid    = row[1] as? String ?? ""
            s.created   = Int(row[2] as? Int32 ?? 0)
            s.updated   = Int(row[3] as? Int32 ?? 0)
            s.idle      = Int(row[4] as? Int32 ?? 0)
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
            "DELETE FROM `\(MySQLSessionConnector.table)` WHERE updated + idle < ?",
            params: [Int(Date().timeIntervalSince1970)]
        )
    }

    // MARK: - Private helpers

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
        defer { stmt.close(); db.close() }
        _ = stmt.prepare(statement: statement)
        for p in params { stmt.bindParam("\(p)") }
        _ = stmt.execute()
        _ = stmt.results()
    }
}
