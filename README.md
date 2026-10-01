# Perfect Sessions (core library) [简体中文](README.zh_CN.md)

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012-lightgray.svg?style=flat" alt="Platforms macOS 12">
    </a>
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache--2.0-lightgrey.svg?style=flat" alt="License Apache-2.0">
    </a>
</p>

The Perfect Session core library, resurrected for Swift 6.2 / macOS 12 — a from-scratch rewrite of
the original API surface targeting the modern Swift toolchain and strict concurrency. This package
**consolidates** what used to be separate `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`
repos into one package with backend products; those repos are superseded by this one. MongoDB
support was added back as a fifth backend built on [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB)
4.x, superseding `Perfect-Session-MongoDB`. `Perfect-Session-CouchDB` was not carried forward.

**Status:** core, in-use package with five fully implemented, tested storage backends
(MySQL/PostgreSQL/Redis/SQLite/MongoDB) — pick whichever matches your existing infrastructure.

## Compatibility with Swift

`Package.swift` declares `swift-tools-version: 6.2` and `platforms: [.macOS(.v12)]`. The default branch is `main`. All 10 targets (5 libraries + 5 test targets) build under `.swiftLanguageMode(.v6)` — full Swift 6 strict-concurrency mode, repo-wide, not opt-in per file. `SessionDriver` is a fully `async`/`await` protocol (`create`/`resume`/`save`/`destroy`/`clean`/`setup` are all `async`, `resume` also `throws`) and is itself `Sendable`; `PerfectSession` and `MemorySessionDriver` are `@unchecked Sendable` with doc-comments justifying the escape hatch (JSON-safe `[String: Any]` payload, NSLock-protected mutable dictionary). No iOS/tvOS/watchOS/Linux platforms are declared — this is macOS-only today.

## Building

Add it to your `Package.swift`:

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

`PerfectSessionCore` has no external database dependency — it provides the `SessionDriver` protocol, the `PerfectSession` request-handling filter, `SessionConfig`, an in-process `MemorySessionDriver` fallback, `AuthFilter`, and `CSRFSecurity`.

## Database-Specific Drivers

Unlike the original upstream project, the database-specific drivers are **not separate repositories** — they are first-class targets/products built directly into this same package, in `Sources/`:

* **PerfectSessionMySQL** — depends on `PerfectMySQL` (`../Perfect-MySQL`). **This is the driver currently configured and exercised in Perfect-Lasso's development/validation testing** (scrubsSite, via `LASSO_SESSION_DRIVER=mysql`).
* **PerfectSessionPostgreSQL** — depends on `PerfectPostgreSQL` (`../Perfect-PostgreSQL`). Fully implemented and tested; not currently the selected driver.
* **PerfectSessionRedis** — depends on `PerfectRedis` (`../Perfect-Redis`) and `swift-log`. Fully implemented and tested; not currently the selected driver.
* **PerfectSessionSQLite** — depends on `PerfectSQLite` (`../Perfect-SQLite`) and `swift-log`. Fully implemented and tested; not currently the selected driver.
* **PerfectSessionMongoDB** — depends on `PerfectMongoDB` 4.x and `swift-log`, and needs libmongoc 2 installed (see the [Perfect-MongoDB README](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)). Each session is a document keyed by its token, with `data` stored as a subdocument. `setup()` adds a TTL index so MongoDB deletes expired sessions itself. Configure it with `MongoDBSessionConnector` (`uri`, `database`, `collection`), or pass a URI or an existing `MongoClientPool` to its initializer. Tests run with `MONGODB_TESTS=1` (and optionally `MONGODB_URI`).

Each driver has its own matching test target (`PerfectSessionMySQLTests`, etc.) alongside `PerfectSessionCoreTests`. Simply depend on the product for the backend you want (see **Building** above) — there is no need to add anything beyond this package.

The CouchDB driver from the original PerfectlySoft project was **not** carried over into this resurrection.

## Further Information

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.
Its backend driver dependencies (`Perfect-MySQL`, `Perfect-PostgreSQL`, `Perfect-Redis`,
`Perfect-SQLite`, `Perfect-MongoDB`) are real `url:` dependencies resolved by SwiftPM automatically — no sibling
checkout needed.
