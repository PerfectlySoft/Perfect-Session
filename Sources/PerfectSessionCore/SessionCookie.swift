import Foundation

/// Builds `Set-Cookie` header values for the session token from `SessionConfig`'s cookie
/// settings, so middleware doesn't assemble the attributes by hand.
public enum SessionCookie {

    /// The `Set-Cookie` value that stores **token**: `name=token; Path=…; [Domain=…;] HttpOnly;
    /// Secure; SameSite=…`, from `SessionConfig`. It has no `Expires`/`Max-Age`, so the browser
    /// drops it when it closes; the server enforces `idle` and `absoluteTimeout` itself.
    ///
    /// `SameSite=None` always adds `Secure` (browsers reject it otherwise), and so does a name
    /// starting with `__Secure-` or `__Host-` (in any case). Returns nil, rather than a header a browser would
    /// misread, if the name isn't a valid cookie name, the token or path holds a character a cookie
    /// can't (`;`, `,`, whitespace, quotes, a backslash or a control character), the domain isn't
    /// a plain host name, or a `__Host-` cookie has a domain or a path other than `/`.
    public static func setCookie(token: String) -> String? {
        build(value: token, extra: nil)
    }

    /// The `Set-Cookie` value that deletes the session cookie (on sign-out), with the same
    /// attributes so the browser matches it.
    public static func expiredCookie() -> String? {
        build(value: "", extra: "Max-Age=0")
    }

    static func build(value: String, extra: String?) -> String? {
        let name   = SessionConfig.name
        let path   = SessionConfig.cookiePath
        let domain = SessionConfig.cookieDomain
        guard isToken(name), value.unicodeScalars.allSatisfy(isCookieOctet),
              !path.isEmpty, path.unicodeScalars.allSatisfy(isPathCharacter),
              domain.isEmpty || isHostName(domain) else { return nil }
        // Browsers recognize the prefixes ignoring case.
        let lowerName = name.lowercased()
        let hostPrefixed = lowerName.hasPrefix("__host-")
        if hostPrefixed && (!domain.isEmpty || path != "/") { return nil }
        let secure = SessionConfig.cookieSecure || SessionConfig.cookieSameSite == .none
            || hostPrefixed || lowerName.hasPrefix("__secure-")
        var parts = ["\(name)=\(value)", "Path=\(path)"]
        if !domain.isEmpty { parts.append("Domain=\(domain)") }
        if let extra { parts.append(extra) }
        if SessionConfig.cookieHTTPOnly { parts.append("HttpOnly") }
        if secure { parts.append("Secure") }
        parts.append("SameSite=\(SessionConfig.cookieSameSite.rawValue)")
        return parts.joined(separator: "; ")
    }

    /// RFC 7230 `token`: visible ASCII except separators.
    static func isToken(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { c in
            c.value > 0x20 && c.value < 0x7f && !"()<>@,;:\\\"/[]?={}".unicodeScalars.contains(c)
        }
    }

    /// RFC 6265 `cookie-octet`.
    static func isCookieOctet(_ c: Unicode.Scalar) -> Bool {
        c.value == 0x21 || (0x23...0x2b).contains(c.value) || (0x2d...0x3a).contains(c.value)
            || (0x3c...0x5b).contains(c.value) || (0x5d...0x7e).contains(c.value)
    }

    /// RFC 6265 `path-value` (any CHAR but controls and `;`), also without spaces or commas.
    static func isPathCharacter(_ c: Unicode.Scalar) -> Bool {
        c.value > 0x20 && c.value < 0x7f && c != ";" && c != ","
    }

    static func isHostName(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { c in
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "-" || c == "."
        }
    }
}
