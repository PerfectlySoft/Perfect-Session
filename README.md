# Perfect Sessions (core library) [简体中文](README.zh_CN.md)

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    </a>
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache--2.0-lightgrey.svg?style=flat" alt="License Apache-2.0">
    </a>
</p>

Session storage and session-security building blocks for Perfect, rewritten for Swift 6 and strict concurrency:
a session model, pluggable storage backends, and framework-independent CSRF, CORS and authentication checks.

This package **consolidates** what used to be separate `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`/`-MongoDB`
repos into one package with a product per backend; those repos are superseded by this one.
`Perfect-Session-CouchDB` was not carried forward.

## Requirements

- Swift 6.2 or later (`swift-tools-version: 6.2`). Every target builds in Swift 6 language mode.
- macOS 12 or later, or Linux. On Linux (tested with Swift 6.4 on Ubuntu 24.04), the core and the MySQL,
  PostgreSQL, Redis and MongoDB backends build. The **SQLite backend is macOS-only for now**, because
  Perfect-SQLite uses the SQLite module from Apple's SDK.
- Each backend needs its database's client library; see the list below.

## Building

Add it to your `Package.swift`, with the backend you want:

``` swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-Session.git", branch: "main"),
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

There is no tagged release of the Swift 6 version yet, so depend on `main`. The `3.x` tags are the pre-rewrite
version. Only the backends you depend on are built: an app using only the MySQL backend never compiles the
others or needs their libraries.

`PerfectSessionCore` has no external database dependency. It provides:

- `PerfectSession`, the session value (token, user ID, timestamps, `data`, CSRF token, and `isValid()` for
  expiry and optional IP/user-agent locks);
- `SessionConfig`, for cookie, expiry, CSRF and CORS settings;
- the `SessionDriver` protocol and `MemorySessionDriver`, an in-process store for development and tests;
- `AuthFilter` (path inclusion/exclusion rules), and `CSRFSecurity`/`CORSSecurity` (origin and host checks on
  header strings).

These don't depend on an HTTP framework. Your server's middleware reads the session cookie, calls a driver
(`create`, `resume`, `save`, `destroy`), and applies the CSRF, CORS and authentication checks.

`SessionDriver` is an `async` protocol: `create`, `resume` (which also `throws`), `save`, `destroy`, `clean` and
`setup`. Drivers are `Sendable`, so one driver instance can be shared across requests.

## Storage backends

Each backend is a target and product in this package, with its own test suite. Configure a backend through its
`…SessionConnector` type. Its tests skip unless the switch shown is set to `1`, along with the connection
variables in that test file.

| Product | Depends on | Needs | Tests |
|---|---|---|---|
| `PerfectSessionMySQL` | [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) | MySQL client library (`libmysqlclient`) | `MYSQL_TESTS` |
| `PerfectSessionPostgreSQL` | [Perfect-PostgreSQL](https://github.com/PerfectlySoft/Perfect-PostgreSQL) | `libpq` | `PG_TESTS` |
| `PerfectSessionRedis` | [Perfect-Redis](https://github.com/PerfectlySoft/Perfect-Redis), `swift-log` | — | `REDIS_TESTS` |
| `PerfectSessionSQLite` | [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite), `swift-log` | macOS (SQLite from the SDK) | `SQLITE_TESTS` |
| `PerfectSessionMongoDB` | [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4.x, `swift-log` | libmongoc 2 ([requirements](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)) | `MONGODB_TESTS` |

The **MongoDB** backend stores each session as a document keyed by its token, with `data` as a subdocument.
Its `setup()` adds a TTL index, so MongoDB deletes expired sessions itself. Besides `MongoDBSessionConnector`
(`uri`, `database`, `collection`), you can pass a URI or an existing `MongoClientPool` to its initializer.

## Further information

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.
