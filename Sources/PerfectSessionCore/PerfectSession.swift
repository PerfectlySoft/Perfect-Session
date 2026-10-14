import Foundation

/// A session token/data container. @unchecked Sendable because data:[String:Any] is JSON-safe.
public struct PerfectSession: @unchecked Sendable {
    public var token      = ""
    public var userid     = ""
    public var created    = 0
    public var updated    = 0
    public var idle       = SessionConfig.idle
    /// The session's values. Store only JSON values: `String`, `Bool`, finite numbers, `NSNull`,
    /// and arrays and `[String: …]` dictionaries of them. If anything else is in here (a `Date`,
    /// a `URL`, NaN, a dictionary with non-string keys), `tojson()` returns `"{}"`, so the
    /// drivers save the session with empty data.
    public var data       = [String: Any]()
    public var ipaddress  = ""
    public var useragent  = ""
    public var _state     = "recover"
    public var _isOAuth2  = SessionConfig.isOAuth2

    public init() {
        let now = Int(Date().timeIntervalSince1970)
        created = now
        updated = now
    }

    /// `data` as JSON text, or `"{}"` if it holds a value JSON can't represent.
    public func tojson() -> String {
        // JSONSerialization raises an Objective-C exception for such values, which `try?` can't
        // catch and which terminates the process, so check first.
        guard JSONSerialization.isValidJSONObject(data),
              let d = try? JSONSerialization.data(withJSONObject: data),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    public mutating func fromjson(_ str: String) {
        guard let d = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        data = obj
    }

    /// When the session expires (seconds since 1970): `updated + idle`, clamped instead of
    /// overflowing, so an `idle` of `Int.max` means "never".
    public var expires: Int {
        let (sum, overflow) = updated.addingReportingOverflow(idle)
        guard overflow else { return sum }
        return idle > 0 ? Int.max : Int.min
    }

    public mutating func touch() {
        updated = Int(Date().timeIntervalSince1970)
    }

    /// True once the session has been idle for `idle` seconds, or (when **absoluteTimeout** is
    /// positive) once that many seconds have passed since it was created, however active it was.
    /// Every driver's `resume` refuses an expired session.
    public func isExpired(at now: Int = Int(Date().timeIntervalSince1970),
                          absoluteTimeout: Int = SessionConfig.absoluteTimeout) -> Bool {
        if expires <= now { return true }
        guard absoluteTimeout > 0 else { return false }
        let (end, overflow) = created.addingReportingOverflow(absoluteTimeout)
        return !overflow && end <= now
    }

    /// Returns false if the session has expired (see `isExpired`) or IP/UA locks fail.
    public func isValid(ipaddress remoteIP: String = "", useragent remoteUA: String = "") -> Bool {
        guard !isExpired() else { return false }
        if SessionConfig.IPAddressLock && !remoteIP.isEmpty && remoteIP != ipaddress { return false }
        if SessionConfig.userAgentLock && !remoteUA.isEmpty && remoteUA != useragent { return false }
        return true
    }

    public mutating func setCSRF() {
        if (data["csrf"] as? String ?? "").isEmpty {
            data["csrf"] = UUID().uuidString
        }
    }
}
