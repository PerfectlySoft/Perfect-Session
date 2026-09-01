import Foundation
import PerfectPostgreSQL
import PerfectSessionCore

public struct PostgreSQLSessionConnector: Sendable {
    nonisolated(unsafe) public static var host: String     = "localhost"
    nonisolated(unsafe) public static var username: String = ""
    nonisolated(unsafe) public static var password: String = ""
    nonisolated(unsafe) public static var database: String = "perfect_sessions"
    nonisolated(unsafe) public static var table: String    = "sessions"
    nonisolated(unsafe) public static var port: Int        = 5432
    private init() {}

    public static func connectionString() -> String {
        let u = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let p = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        let h = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        let d = database.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? database
        return "postgresql://\(u):\(p)@\(h):\(port)/\(d)"
    }
}

public final class PostgreSQLSessionDriver: SessionDriver, @unchecked Sendable {
    public init() {}

    public func setup() async {
        let sql = """
            CREATE TABLE IF NOT EXISTS "\(PostgreSQLSessionConnector.table)" (
                "token"     varchar NOT NULL,
                "userid"    varchar,
                "created"   int4 NOT NULL DEFAULT 0,
                "updated"   int4 NOT NULL DEFAULT 0,
                "idle"      int4 NOT NULL DEFAULT 0,
                "data"      text,
                "ipaddress" varchar,
                "useragent" text,
                PRIMARY KEY ("token")
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
            "INSERT INTO \"\(PostgreSQLSessionConnector.table)\" (token,userid,created,updated,idle,data,ipaddress,useragent) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
            params: [session.token, session.userid, session.created, session.updated,
                     session.idle, session.tojson(), session.ipaddress, session.useragent]
        )
        return session
    }

    public func resume(token: String) async throws -> PerfectSession {
        let db = connect()
        defer { db.close() }
        let result = db.exec(
            statement: "SELECT token,userid,created,updated,idle,data,ipaddress,useragent FROM \"\(PostgreSQLSessionConnector.table)\" WHERE token = $1",
            params: [token]
        )
        defer { result.clear() }
        guard result.numTuples() > 0 else { throw InvalidSessionError() }
        var s = PerfectSession()
        s.token     = result.getFieldString(tupleIndex: 0, fieldIndex: 0) ?? ""
        s.userid    = result.getFieldString(tupleIndex: 0, fieldIndex: 1) ?? ""
        s.created   = result.getFieldInt(tupleIndex: 0, fieldIndex: 2)    ?? 0
        s.updated   = result.getFieldInt(tupleIndex: 0, fieldIndex: 3)    ?? 0
        s.idle      = result.getFieldInt(tupleIndex: 0, fieldIndex: 4)    ?? 0
        if let d = result.getFieldString(tupleIndex: 0, fieldIndex: 5) { s.fromjson(d) }
        s.ipaddress = result.getFieldString(tupleIndex: 0, fieldIndex: 6) ?? ""
        s.useragent = result.getFieldString(tupleIndex: 0, fieldIndex: 7) ?? ""
        s._state    = "resume"
        return s
    }

    public func save(_ session: PerfectSession) async {
        exec(
            "UPDATE \"\(PostgreSQLSessionConnector.table)\" SET userid=$1,updated=$2,idle=$3,data=$4 WHERE token=$5",
            params: [session.userid, session.updated, session.idle, session.tojson(), session.token]
        )
    }

    public func destroy(token: String) async {
        exec("DELETE FROM \"\(PostgreSQLSessionConnector.table)\" WHERE token=$1", params: [token])
    }

    public func clean() async {
        exec(
            "DELETE FROM \"\(PostgreSQLSessionConnector.table)\" WHERE updated + idle < $1",
            params: [Int(Date().timeIntervalSince1970)]
        )
    }

    // MARK: - Private helpers

    private func connect() -> PGConnection {
        let db = PGConnection()
        _ = db.connectdb(PostgreSQLSessionConnector.connectionString())
        return db
    }

    private func exec(_ statement: String, params: [Any]) {
        let db = connect()
        _ = db.exec(statement: statement, params: params)
        db.close()
    }
}
