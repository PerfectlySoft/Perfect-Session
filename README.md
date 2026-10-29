# Perfect Sessions (core library) [简体中文](README.zh_CN.md)

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-6.2%2B-orange.svg?style=flat" alt="Swift 6.2+">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    </a>
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache--2.0-lightgrey.svg?style=flat" alt="License Apache-2.0">
    </a>
</p>

Session storage and session-security building blocks for Perfect, rewritten for Swift 6 and strict concurrency:
a session model, pluggable storage backends, and framework-independent CSRF, CORS, cookie and authentication
helpers.

This package **consolidates** what used to be separate `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`/`-MongoDB`
repos into one package with a product per backend; those repos are superseded by this one.
`Perfect-Session-CouchDB` was not carried forward.

## Requirements

- Swift 6.2 or later (`swift-tools-version: 6.2`). Every target builds in Swift 6 language mode.
- macOS 12 or later, or Linux. CI builds and tests with Swift 6.2 and 6.4 on Ubuntu 24.04 (every backend against
  a live server) and with Xcode 26.0.1 and 26.6 on macOS.
- Each backend needs its database's client library; see [Storage backends](#storage-backends).

## Installation

Add the package and the backend you want:

``` swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-Session.git", from: "4.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PerfectSessionCore", package: "Perfect-Session"),
            // plus whichever backend driver(s) you need, e.g.:
            .product(name: "PerfectSessionMySQL", package: "Perfect-Session"),
        ]
    )
]
```

Only the backends you depend on are built: an app using only the MySQL backend never compiles the others or
needs their libraries.

## What's in the core

`PerfectSessionCore` has no external database dependency. It provides:

- `PerfectSession`, the session value: token, user ID, timestamps, `data`, a CSRF token, `isExpired()`, and
  `isValid()` (expiry plus optional IP-address and user-agent locks);
- `SessionConfig`, for cookie, expiry, CSRF and CORS settings;
- the `SessionDriver` protocol and `MemorySessionDriver`, an in-process store for development and tests;
- `SessionCookie`, which builds the `Set-Cookie` values for the session cookie from `SessionConfig`;
- `AuthFilter` (which paths require authentication), and `CSRFSecurity`/`CORSSecurity` (CSRF token, origin
  and host checks on header strings).

None of these depend on an HTTP framework. Your server's middleware reads the session cookie, calls a driver,
and applies the checks.

`SessionDriver` is an `async` protocol: `create`, `resume` (which also `throws`), `save`, `destroy`,
`regenerate`, `clean` and `setup`. Drivers are `Sendable`, so one driver instance can be shared across requests.

### Session security

- **Tokens.** Session and CSRF tokens are 32 bytes from the system's secure random number generator, as 64 hex
  digits (`PerfectSession.newToken()`).
- **Expiry is enforced by the server.** Every driver's `resume` throws `InvalidSessionError` for a session that has
  gone `idle` seconds (`SessionConfig.idle`, one day by default) without a `save` (every driver's `save` renews it),
  or, if you set `SessionConfig.absoluteTimeout`, that many seconds after it was created, however active it is.
  Times are seconds since 1970, so the process's time zone doesn't matter. `clean()` deletes expired sessions from
  storage (both limits); the MongoDB TTL index and Redis key TTLs follow both limits too.
- **Fixation.** `resume` only returns sessions the driver stored, and `save` only updates a stored session (so a
  save racing a logout can't bring it back). Call `regenerate(_:)` when a user signs in or gains privileges, and
  send the client the new token: it moves the session (user, data, idle time and creation time, so the absolute
  timeout keeps running) to a new token and CSRF token and destroys the old one.
- **CSRF.** Every session has a CSRF token in `data["csrf"]` (`resume` adds one if a stored session lacks it).
  Send it to your pages, have state-changing requests send it back (a header or form field), and compare with
  `CSRFSecurity.tokenMatches(_:_:)`, which takes the same time wherever the tokens differ. Also check the `Origin`
  header with `CSRFSecurity.isValid(origin:host:)`: it compares scheme, host and port, ignoring case and default
  ports, and never accepts an empty or `null` origin.
- **Authentication paths.** `AuthFilter.requiresAuthentication(_:using:)` says whether a request path needs a
  signed-in user. Paths are compared by `/`-separated segment, ignoring empty and `.` segments and (by default,
  `AuthenticationConfig.caseInsensitive`) ASCII case, because Perfect-NIO 0.1 routes `/ADMIN` to an `/admin`
  handler. `include("/admin")` covers `/admin` and everything below it, but not `/administrator`; `"/admin/*"`
  means the same, and `"*"` (or `"/"`) covers every path. Exclusions override inclusions. `*` is a wildcard only as
  a whole final segment: an inclusion like `"*.json"` or `"/admin*"` makes every path require authentication, and
  such an exclusion matches nothing. When anything is protected, a path with a `..` segment, `%`, `;` or `\`
  always requires authentication, since servers decode those differently. Pass the path without its query string.
  (`shouldWeAccept`, which returns true when authentication is *required*, is deprecated.)
- **CORS.** `CORSSecurity.isAcceptable(origin:)` matches `SessionConfig.CORS.acceptableHostnames` ignoring case;
  each `*` in a pattern matches any run of characters. Anchor patterns with the scheme and the full host:
  a trailing `*`, as in `"https://example.com*"`, also matches `https://example.com.evil.net`. `"*"` accepts every
  origin, `null` included. Sending the `Access-Control-*` headers, and deciding whether to allow credentials, is up
  to your middleware.
- **Cookies.** `SessionCookie.setCookie(token:)` and `expiredCookie()` apply `SessionConfig`'s `name`,
  `cookiePath`, `cookieDomain`, `cookieSecure`, `cookieHTTPOnly` (default on) and `cookieSameSite` (default
  `Strict`). `SameSite=None` and the `__Secure-`/`__Host-` name prefixes (in any case) always add `Secure`; set `cookieSecure`
  yourself when you serve over HTTPS. They return nil instead of a malformed header if a setting or the token holds
  a character a cookie can't.
- **Session data** is stored as JSON. Keep `data` to JSON values (`String`, `Bool`, finite numbers, `NSNull`, and
  arrays and `[String: …]` dictionaries of them). A top-level key whose value is anything else, such as a `Date`,
  isn't saved, and its name (never its value) is logged; the other keys and the CSRF token are saved.
- **Logs** identify a session by `PerfectSession.logID(_:)`, a 12-digit SHA-256 prefix of its token, never by the
  token itself.
- **Configuration** (`SessionConfig`, `AuthFilter.authenticationConfig` and each `…SessionConnector`) is global
  state: set it once at startup, before serving requests. The checks also take explicit values
  (`isValid(…, ipAddressLock:userAgentLock:)`, `CSRFSecurity.isValid(…, acceptableHostnames:)`,
  `CORSSecurity.isAcceptable(…, config:)`).

### Using it with Perfect-NIO

A session filter in [Perfect-NIO](https://github.com/PerfectlySoft/Perfect-NIO) 0.2's route style:

``` swift
import PerfectNIO
import PerfectSessionCore

let driver: any SessionDriver = MemorySessionDriver()   // or any backend's driver

struct RequestSession: Sendable {
    var session: PerfectSession
    let isNew: Bool
}

@Sendable func loadSession(_ req: any HTTPRequest) async throws -> RequestSession {
    // A CORS preflight (OPTIONS) carries no cookies. Answer it before a session is created for it.
    if req.method == .OPTIONS { throw TerminationType.criteriaFailed(.noContent) }
    let ip = req.remoteAddress?.ipAddress ?? ""
    let ua = req.headers["User-Agent"].first ?? ""
    if let token = req.cookies[SessionConfig.name],
       let session = try? await driver.resume(token: token),
       session.isValid(ipaddress: ip, useragent: ua) {
        return RequestSession(session: session, isNew: false)
    }
    return RequestSession(session: await driver.create(ipaddress: ip, useragent: ua), isNew: true)
}

let routes: Routes<HTTPRequest, HTTPOutput> = root(loadSession).map { state -> HTTPOutput in
    var session = state.session
    session.data["visits"] = (session.data["visits"] as? Int ?? 0) + 1
    await driver.save(session)
    let headers = state.isNew ? SessionCookie.setCookie(token: session.token).map { [("Set-Cookie", $0)] } ?? [] : []
    return TextOutput("visits: \(session.data["visits"] ?? 0)", headers: headers)
}
```

Browsers send a preflight `OPTIONS` request, without cookies, before a cross-origin request with a custom
header such as `X-CSRF-Token`. Without the check at the top of `loadSession`, every preflight would create and
store a new session and run the handler. The empty `204` above sends no `Access-Control-*` headers, so the browser
won't go on to send a cross-origin request. If you accept those, answer preflights from origins that pass
`CORSSecurity.isAcceptable(origin:)` with the `Access-Control-*` headers your app needs.

Authentication and CSRF checks, after `loadSession`:

``` swift
let auth: AuthenticationConfig = {
    var config = AuthenticationConfig()
    config.include("/account")
    config.exclude("/account/login")
    return config
}()

@Sendable func checkRequest(_ state: RequestSession, _ req: any HTTPRequest) throws -> RequestSession {
    if AuthFilter.requiresAuthentication(req.path, using: auth), state.session.userid.isEmpty {
        throw ErrorOutput(status: .unauthorized, description: "Sign in first")
    }
    if req.method != .GET && req.method != .HEAD {
        // The page sent the session's data["csrf"] back in a header (or a form field).
        let expected = state.session.data["csrf"] as? String ?? ""
        let presented = req.headers["X-CSRF-Token"].first ?? ""
        guard CSRFSecurity.tokenMatches(presented, expected),
              CSRFSecurity.isValid(origin: req.headers["Origin"].first ?? "",
                                   host: req.headers["Host"].first ?? "") else {
            throw ErrorOutput(status: .forbidden, description: "CSRF check failed")
        }
    }
    return state
}

let checked = root(loadSession).request(checkRequest)
```

## Storage backends

Each backend is a target and product in this package, with its own test suite. Configure a backend through its
`…SessionConnector` type, once, at startup.

| Product | Depends on | Needs |
|---|---|---|
| `PerfectSessionMySQL` | [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) 4 | MySQL client library (`libmysqlclient`) |
| `PerfectSessionPostgreSQL` | [Perfect-PostgreSQL](https://github.com/PerfectlySoft/Perfect-PostgreSQL) 5 | `libpq` |
| `PerfectSessionRedis` | [Perfect-Redis](https://github.com/PerfectlySoft/Perfect-Redis) 4, `swift-log` | — |
| `PerfectSessionSQLite` | [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite) 6, `swift-log` | `libsqlite3-dev` on Linux |
| `PerfectSessionMongoDB` | [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4, `swift-log` | libmongoc 2 ([requirements](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)) |

On macOS, `mysql-client` and `libpq` from Homebrew are keg-only: set
`PKG_CONFIG_PATH=$(brew --prefix libpq)/lib/pkgconfig:$(brew --prefix mysql-client)/lib/pkgconfig`.

**MySQL, PostgreSQL and SQLite** store a session per row in `table` (default `sessions`), created by `setup()`.
Every value is bound as a parameter. `created`, `updated` and `idle` are 64-bit (`bigint`/`int8`); see
[Migrating](#migrating-from-earlier-versions) for tables created before 4.0. `MySQLSessionConnector.port` must be
1–65535. PostgreSQL connects with `PostgreSQLSessionConnector.connectionString()`, which percent-encodes the user
name, password and database.

The **Redis** backend stores each session as JSON under `RedisSessionConnector.keyPrefix` + token (default prefix
`perfect-session:`, so a client's token can't name your application's own keys), with a TTL of the session's
`idle` (or until the absolute timeout, if sooner; at most about 31,700 years), renewed by each `save`. Each call
opens its own connection. `RedisSessionConnector.commandTimeout` (seconds, default 5; nil waits indefinitely) is
passed to Perfect-Redis: a call that takes longer throws, its connection is closed, and the driver logs the error
(`resume` throws `InvalidSessionError`).

The **MongoDB** backend stores each session as a document keyed by its token, with `data` as a subdocument.
Its `setup()` adds a TTL index, so MongoDB deletes expired sessions itself. Besides `MongoDBSessionConnector`
(`uri`, `database`, `collection`), you can pass a URI or an existing `MongoClientPool` to its initializer;
`MongoDBSessionDriver()` traps if `MongoDBSessionConnector.uri` isn't a valid connection string, while
`init(uri:database:collection:)` throws. libmongoc rejects an empty key, and a key is cut short at a NUL, so keys
in `data` are escaped at every depth: `%` is stored as `%25`, NUL as `%00`, and the empty key as `%`. Other keys,
`$`-prefixed and dotted ones included, are stored as is, so queries such as `data.role` keep working.

### Migrating from Perfect-Session-MongoDB

The archived `Perfect-Session-MongoDB` stored each session under its own `_id`, with the token in a `token`
field, `data` as JSON text, and no expiry date. The MongoDB backend can't read those documents, so existing
sessions end when you switch and users sign in again. The TTL index never removes them either, so if you point
the new driver at the old collection, `setup()` deletes them: documents with a string `token`, string `data`,
`created`, `updated` and `idle` fields, and no `expiresAt`. Run `setup()` again once no old instances are left
writing to the collection. To keep the old documents, use a different `collection`.

## Running the tests

``` sh
swift test        # core tests; each backend's live suite reports as skipped
```

Each backend's live suite runs when its switch is `1`. It drops and recreates its test table or collection, so
point it at a throwaway server:

| Backend | Switch | Connection variables |
|---|---|---|
| MySQL | `MYSQL_TESTS` | `MYSQL_HOST`, `MYSQL_PORT` (required), `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` |
| PostgreSQL | `PG_TESTS` | `PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASSWORD`, `PG_DATABASE` |
| Redis | `REDIS_TESTS` | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
| MongoDB | `MONGODB_TESTS` | `MONGODB_URI` |
| SQLite | `SQLITE_TESTS` | — (a temporary file) |

With `SESSION_REQUIRE_LIVE=1`, as in CI, a backend whose switch isn't set, or whose server can't be reached, fails
the run instead of skipping.

## Known limitations

- **NUL in user IDs and user agents.** PostgreSQL text can't hold a NUL character (the write fails, so the session
  isn't stored or saved), and SQLite's text binding stops at it. Session `data` is unaffected (it's JSON).
- **`AuthFilter` sees only the path you pass.** It doesn't percent-decode (a path with `%` requires authentication
  when anything is protected), and with `caseInsensitive` off it assumes your router is case-sensitive too.
- **No TLS settings for MySQL or PostgreSQL.** `MySQLSessionConnector` and `PostgreSQLSessionConnector` have no
  TLS/`sslmode` options, so the connection uses the client library's defaults (libpq's is `prefer`, which doesn't
  verify the server). Use a trusted network, a local socket, or a TLS tunnel.
- **Database errors aren't logged by the MySQL and PostgreSQL drivers**: a failed write is silent.
- **MySQL compares tokens with the column's collation**, case-insensitively by default; tokens are lowercase hex, so
  this only means an uppercased token also resumes the session.
- **Global configuration.** The settings are `nonisolated(unsafe)` statics: changing them while requests are being
  served is a data race.
- **`PerfectSession.data` is `[String: Any]`.** `PerfectSession` is `@unchecked Sendable` on the understanding that
  `data` holds only JSON values.

## Migrating from earlier versions

### From 3.x

4.0 is a rewrite for Swift 6. The 3.x module `PerfectSession`, with its Perfect-HTTPServer request and response
filters (`SessionMemoryDriver`, `CSRFFilter`, `isValid(_ request:)`), and the separate per-backend repositories are
replaced by this package:

- Depend on `PerfectSessionCore` plus a backend product, instead of `Perfect-Session` and a
  `Perfect-Session-<Backend>` package.
- `PerfectSessionManager` is now `SessionDriver`, an `async` `Sendable` protocol that also requires
  `create(ipaddress:useragent:)` (and has `setup`, `clean` and `regenerate`, with default implementations).
- `SessionConfig.couchDatabase` and `mongoCollection` are gone: configure the backend's `…SessionConnector`
  (`MongoDBSessionConnector.collection`). `cookieSameSite` is a `CookieSameSite` (was `HTTPCookie.SameSite`), and
  `CORS.methods` is `[String]` (was `[HTTPMethod]`).
- These settings still exist but have no effect in 4.0 and are deprecated: `SessionConfig.CSRF.failAction`,
  `checkState`, `checkHeaders` and `requireToken`; `SessionConfig.CORS.methods`, `customHeaders`,
  `withCredentials` and `maxAge`; `SessionConfig.purgeInterval`, `healthCheckRoute` and `isOAuth2`;
  `PerfectSession._isOAuth2`; `AuthenticationConfig.denied`. Your middleware does what they used to configure.
- `AuthFilter.shouldWeAccept` is deprecated for `requiresAuthentication`, which matches by path segment, ignoring
  case (see [Session security](#session-security)).
- There are no HTTP filters. Write a small middleware for your server (see
  [Using it with Perfect-NIO](#using-it-with-perfect-nio)) that calls a `SessionDriver`, `SessionCookie`,
  `CSRFSecurity`, `CORSSecurity` and `AuthFilter`.
- Drivers are `async`: `try await driver.resume(token:)`, `await driver.save(_:)` (was `save(session:)`),
  `await driver.destroy(token:)`. `isValid` takes the client's IP address and user agent as strings.
- Logging uses swift-log instead of Perfect-Logger.
- Tokens are 64 hex digits instead of UUIDs, and stored 3.x sessions aren't migrated: users sign in again.

### From the Swift 6 `main` branch

If you used `main` before 4.0.0:

- **Expired sessions are refused.** `resume` throws `InvalidSessionError` once a session's idle time has run out,
  instead of returning it for you to check with `isValid()`.
- **Redis keys have a prefix.** Sessions are stored under `perfect-session:<token>`, so sessions stored by `main`
  aren't found (users sign in again). Set `RedisSessionConnector.keyPrefix = ""` to keep the old keys, but then a
  client's token can name any key in that database.
- **Redis TTLs follow the session's `idle`** rather than `SessionConfig.idle`, and a session whose `idle` is 0 or
  less is deleted rather than stored without a TTL.
- **`MemorySessionDriver.save` only updates** a session it has stored, like the other drivers.
- **Every `save` renews the idle time** (only Redis did); `regenerate` keeps the creation time.
- **Redis calls time out after 5 seconds** by default (`RedisSessionConnector.commandTimeout`; set nil for none).
- **Session data JSON can't hold** loses only the offending keys, not all of `data`.
- **`AuthFilter`** matches by segment, ignoring case; `CSRFSecurity.isValid` compares scheme and port.
- **Tokens are 64 hex digits** (they were UUIDs).
- **Wider columns.** Tables that `setup()` created before 4.0 keep 32-bit `created`/`updated`/`idle` columns, which
  can't hold an `idle` past about 68 years or times after 2038. Widen them:

  ``` sql
  -- MySQL
  ALTER TABLE `sessions` MODIFY `created` bigint NOT NULL DEFAULT 0, MODIFY `updated` bigint NOT NULL DEFAULT 0,
      MODIFY `idle` bigint NOT NULL DEFAULT 0;
  -- PostgreSQL
  ALTER TABLE "sessions" ALTER COLUMN "created" TYPE int8, ALTER COLUMN "updated" TYPE int8,
      ALTER COLUMN "idle" TYPE int8;
  ```

## Legacy

The pre-Swift-6 code (3.1.5 plus the later OAuth2 flag) is preserved on the [`legacy`](../../tree/legacy) branch.
Stay on 3.x if you can't move to Swift 6.2 yet.
