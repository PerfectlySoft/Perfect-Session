import Foundation
import Logging

private let logger = Logger(label: "perfect.session")

/// A session: its token, user, timestamps and data.
///
/// `@unchecked Sendable` because `data` is `[String: Any]`. That holds only while `data` holds JSON
/// values (see `data`), which are value types or immutable Foundation objects; don't put a
/// mutable reference type in it.
public struct PerfectSession: @unchecked Sendable {
    public var token      = ""
    public var userid     = ""
    public var created    = 0
    public var updated    = 0
    public var idle       = SessionConfig.idle
    /// The session's values. Store only JSON values: `String`, `Bool`, finite numbers, `NSNull`,
    /// and arrays and `[String: …]` dictionaries of them. A top-level key whose value holds
    /// anything else (a `Date`, a `URL`, NaN, a dictionary with non-string keys) isn't saved; its
    /// name is logged. See `jsonSafeData()`.
    public var data       = [String: Any]()
    public var ipaddress  = ""
    public var useragent  = ""
    public var _state     = "recover"
    @available(*, deprecated, message: "Has no effect in 4.0: nothing reads it, and it isn't stored.")
    public var _isOAuth2  = false

    public init() {
        let now = Int(Date().timeIntervalSince1970)
        created = now
        updated = now
    }

    /// `data` without the top-level keys whose values JSON can't hold, which are logged by name
    /// (never by value). The CSRF token is never dropped: if it isn't a JSON value, a new one
    /// replaces it.
    public func jsonSafeData() -> [String: Any] {
        // JSONSerialization raises an Objective-C exception for such values, which `try?` can't
        // catch and which terminates the process, so check each one first.
        guard !JSONSerialization.isValidJSONObject(data) else { return data }
        var safe = [String: Any]()
        var dropped = [String]()
        for (key, value) in data {
            if JSONSerialization.isValidJSONObject([key: value]) {
                safe[key] = value
            } else if key == "csrf" {
                safe[key] = PerfectSession.newToken()
            } else {
                dropped.append(key)
            }
        }
        if !dropped.isEmpty {
            logger.warning("session data not saved: values JSON can't hold",
                           metadata: ["keys": .array(dropped.sorted().map { .string($0) })])
        }
        return safe
    }

    /// `jsonSafeData()` as JSON text.
    public func tojson() -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: jsonSafeData()),
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
        expiry(absoluteTimeout: absoluteTimeout) <= now
    }

    /// When the session expires (seconds since 1970), taking **absoluteTimeout** into account:
    /// the earlier of `expires` and `created + absoluteTimeout` (when that's positive).
    public func expiry(absoluteTimeout: Int = SessionConfig.absoluteTimeout) -> Int {
        guard absoluteTimeout > 0 else { return expires }
        let (end, overflow) = created.addingReportingOverflow(absoluteTimeout)
        return overflow ? expires : min(expires, end)
    }

    /// Returns false if the session has expired (see `isExpired`) or IP/UA locks fail. The locks
    /// default to `SessionConfig.IPAddressLock` and `SessionConfig.userAgentLock`.
    public func isValid(ipaddress remoteIP: String = "", useragent remoteUA: String = "",
                        ipAddressLock: Bool = SessionConfig.IPAddressLock,
                        userAgentLock: Bool = SessionConfig.userAgentLock) -> Bool {
        guard !isExpired() else { return false }
        if ipAddressLock && !remoteIP.isEmpty && remoteIP != ipaddress { return false }
        if userAgentLock && !remoteUA.isEmpty && remoteUA != useragent { return false }
        return true
    }

    /// A new session or CSRF token: 32 bytes (256 bits) from the system's secure random number
    /// generator, as 64 lowercase hex digits.
    ///
    /// Not `UUID()`: on Linux, Foundation's UUID reads /dev/urandom and ignores a failed open,
    /// so in a process out of file descriptors every UUID is 00000000-0000-4000-8000-000000000000.
    /// `SystemRandomNumberGenerator` uses getrandom(2) or arc4random_buf(3) and never returns
    /// unfilled bytes.
    public static func newToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let hex = Array("0123456789abcdef".utf8)
        var digits = [UInt8]()
        digits.reserveCapacity(64)
        for _ in 0..<4 {
            var word = generator.next()
            for _ in 0..<8 {
                let byte = UInt8(truncatingIfNeeded: word)
                digits.append(hex[Int(byte >> 4)])
                digits.append(hex[Int(byte & 0x0f)])
                word >>= 8
            }
        }
        return String(decoding: digits, as: UTF8.self)
    }

    public mutating func setCSRF() {
        if (data["csrf"] as? String ?? "").isEmpty {
            data["csrf"] = PerfectSession.newToken()
        }
    }
}
