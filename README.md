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

The Perfect Session core library, resurrected for Swift 6.2 / macOS 12. This is `taplin/Perfect-Session`, a fork within the [Perfect-Resurrection](https://github.com/taplin/Perfect-Resurrection) project — not the original PerfectlySoft codebase evolving, but a from-scratch rewrite of its API surface targeting the modern Swift toolchain and strict concurrency.

**Status: core, in-use package.** [Perfect-Lasso](https://github.com/taplin/Perfect-Lasso) — a Swift reimplementation of the Lasso language, still in active development and not yet production-ready, though validated against real code from multiple production e-commerce sites — depends on this package directly (via `.package(url:, branch: "main")`) to back its session handling. Of the four storage backends this package ships, **MySQL is the one actually configured and exercised in Perfect-Lasso's development/validation setup** (`LASSO_SESSION_DRIVER=mysql`); PostgreSQL, Redis, and SQLite are real, fully implemented, tested alternatives available for a future backend swap, not currently the selected backend.

## Compatibility with Swift

`Package.swift` declares `swift-tools-version: 6.2` and `platforms: [.macOS(.v12)]`. The default branch is `main`. All 10 targets (5 libraries + 5 test targets) build under `.swiftLanguageMode(.v6)` — full Swift 6 strict-concurrency mode, repo-wide, not opt-in per file. `SessionDriver` is a fully `async`/`await` protocol (`create`/`resume`/`save`/`destroy`/`clean`/`setup` are all `async`, `resume` also `throws`) and is itself `Sendable`; `PerfectSession` and `MemorySessionDriver` are `@unchecked Sendable` with doc-comments justifying the escape hatch (JSON-safe `[String: Any]` payload, NSLock-protected mutable dictionary). No iOS/tvOS/watchOS/Linux platforms are declared — this is macOS-only today.

## Building

Add it to your `Package.swift`:

``` swift
dependencies: [
    .package(url: "https://github.com/taplin/Perfect-Session.git", branch: "main"),
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

Each driver has its own matching test target (`PerfectSessionMySQLTests`, etc.) alongside `PerfectSessionCoreTests`. Simply depend on the product for the backend you want (see **Building** above) — there is no need to add anything beyond this package.

CouchDB and MongoDB drivers from the original PerfectlySoft project were **not** carried over into this resurrection and do not exist anywhere in this repo.

## Further Information

This package is part of Tim's [Perfect-Resurrection](https://github.com/taplin/Perfect-Resurrection) project, a Swift 6 resurrection of the archived PerfectlySoft framework family. Sibling path-dependencies (`Perfect-MySQL`, `Perfect-PostgreSQL`, `Perfect-Redis`, `Perfect-SQLite`) are expected to be checked out as sibling directories on disk, matching the relative `../` paths in `Package.swift`.
