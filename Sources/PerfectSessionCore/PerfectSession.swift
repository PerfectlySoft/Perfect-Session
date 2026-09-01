import Foundation

/// A session token/data container. @unchecked Sendable because data:[String:Any] is JSON-safe.
public struct PerfectSession: @unchecked Sendable {
    public var token      = ""
    public var userid     = ""
    public var created    = 0
    public var updated    = 0
    public var idle       = SessionConfig.idle
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

    public func tojson() -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: data),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    public mutating func fromjson(_ str: String) {
        guard let d = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        data = obj
    }

    public mutating func touch() {
        updated = Int(Date().timeIntervalSince1970)
    }

    /// Returns false if the session has expired or IP/UA locks fail.
    public func isValid(ipaddress remoteIP: String = "", useragent remoteUA: String = "") -> Bool {
        let now = Int(Date().timeIntervalSince1970)
        guard (updated + idle) > now else { return false }
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
