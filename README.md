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
- macOS 12 or later, or Linux. Every backend builds on Linux (tested with Swift 6.4 on Ubuntu 26.04).
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
| `PerfectSessionSQLite` | [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite), `swift-log` | macOS, Linux (`libsqlite3-dev` on Linux) | `SQLITE_TESTS` |
| `PerfectSessionMongoDB` | [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4.x, `swift-log` | libmongoc 2 ([requirements](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)) | `MONGODB_TESTS` |

The **MongoDB** backend stores each session as a document keyed by its token, with `data` as a subdocument.
Its `setup()` adds a TTL index, so MongoDB deletes expired sessions itself. Besides `MongoDBSessionConnector`
(`uri`, `database`, `collection`), you can pass a URI or an existing `MongoClientPool` to its initializer.
`save` only updates a session that still exists, so a save that races a logout can't bring the session back;
a session that was never stored (its `create` failed) or has already expired isn't stored by `save` either.
libmongoc rejects an empty key, and a key is cut short at a NUL, so keys in `data` are escaped at every depth:
`%` is stored as `%25`, NUL as `%00`, and the empty key as `%`. Other keys are stored as is, so queries such as
`data.role` keep working.

### Migrating from Perfect-Session-MongoDB

The archived `Perfect-Session-MongoDB` stored each session under its own `_id`, with the token in a `token`
field, `data` as JSON text, and no expiry date. The MongoDB backend can't read those documents, so existing
sessions end when you switch and users sign in again. The TTL index never removes them either, so if you point
the new driver at the old collection, `setup()` deletes them: documents with a string `token`, string `data`,
`created`, `updated` and `idle` fields, and no `expiresAt`. Run `setup()` again once no old instances are left
writing to the collection. To keep the old documents, use a different `collection`.

## Further information

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.
