# Perfect Sessions（核心库） [English](README.md)

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

Perfect Session 核心库，针对 Swift 6.2 / macOS 12 重新复活——这是对原有 API 的一次从零重写，面向现代 Swift
工具链与严格并发检查。本包把过去分散的 `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`
仓库**合并**为一个包含多个后端产品的包，上述仓库均已被本包取代。MongoDB 支持已作为第五个后端重新加入，
基于 [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4.x 构建，取代了 `Perfect-Session-MongoDB`。
`Perfect-Session-CouchDB` 没有被沿用。

**状态：** 核心、在用的包，提供五个已完整实现并经过测试的存储后端（MySQL/PostgreSQL/Redis/SQLite/MongoDB）——
选择与你现有基础设施相匹配的即可。

## Swift 兼容性

`Package.swift` 声明了 `swift-tools-version: 6.2` 和 `platforms: [.macOS(.v12)]`，默认分支为 `main`。全部 10 个
目标（5 个库 + 5 个测试目标）都在 `.swiftLanguageMode(.v6)` 下编译——在整个仓库范围内启用完整的 Swift 6
严格并发模式，而不是按文件选择启用。`SessionDriver` 是一个完全基于 `async`/`await` 的协议
（`create`/`resume`/`save`/`destroy`/`clean`/`setup` 都是 `async`，`resume` 还会 `throws`），并且本身遵循
`Sendable`；`PerfectSession` 和 `MemorySessionDriver` 标注为 `@unchecked Sendable`，并以文档注释说明使用这一
例外的理由（负载 `[String: Any]` 可安全序列化为 JSON；可变字典由 NSLock 保护）。目前未声明 iOS/tvOS/watchOS/Linux
平台——当前仅支持 macOS。

## 构建

把它加入你的 `Package.swift`：

``` swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-Session.git", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PerfectSessionCore", package: "Perfect-Session"),
            // 再加上你需要的后端驱动，例如：
            .product(name: "PerfectSessionMySQL", package: "Perfect-Session"),
        ]
    )
]
```

`PerfectSessionCore` 不依赖任何外部数据库——它提供 `SessionDriver` 协议、处理请求的 `PerfectSession` 过滤器、
`SessionConfig`、进程内的 `MemorySessionDriver` 后备实现、`AuthFilter` 以及 `CSRFSecurity`。

## 各数据库专用驱动

与原先的上游项目不同，各数据库专用驱动**不再是独立的仓库**——它们是直接内置在本包 `Sources/` 中的一等目标/产品：

* **PerfectSessionMySQL** —— 依赖 `PerfectMySQL`（`../Perfect-MySQL`）。**这是 Perfect-Lasso 开发/验证测试中当前
  配置并实际使用的驱动**（scrubsSite，通过 `LASSO_SESSION_DRIVER=mysql`）。
* **PerfectSessionPostgreSQL** —— 依赖 `PerfectPostgreSQL`（`../Perfect-PostgreSQL`）。已完整实现并测试；当前未被选用。
* **PerfectSessionRedis** —— 依赖 `PerfectRedis`（`../Perfect-Redis`）和 `swift-log`。已完整实现并测试；当前未被选用。
* **PerfectSessionSQLite** —— 依赖 `PerfectSQLite`（`../Perfect-SQLite`）和 `swift-log`。已完整实现并测试；当前未被选用。
* **PerfectSessionMongoDB** —— 依赖 `PerfectMongoDB` 4.x 和 `swift-log`，并需要安装 libmongoc 2（参见
  [Perfect-MongoDB 的 README](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)）。每个会话是一个以其
  令牌为键的文档，`data` 以子文档形式存储。`setup()` 会添加 TTL 索引，让 MongoDB 自动删除过期会话。可通过
  `MongoDBSessionConnector`（`uri`、`database`、`collection`）进行配置，也可以向其初始化方法传入 URI 或现有的
  `MongoClientPool`。设置 `MONGODB_TESTS=1`（以及可选的 `MONGODB_URI`）即可运行测试。

每个驱动都有对应的测试目标（`PerfectSessionMySQLTests` 等），与 `PerfectSessionCoreTests` 并列。只需依赖你所需后端
的产品即可（见上文**构建**）——除本包之外无需添加任何其他内容。

原 PerfectlySoft 项目中的 CouchDB 驱动**没有**被移植到这次复活版本中。

## 更多信息

本包在 Swift 6 之前的版本保留在 [`legacy`](../../tree/legacy) 分支上。
其后端驱动依赖（`Perfect-MySQL`、`Perfect-PostgreSQL`、`Perfect-Redis`、`Perfect-SQLite`、`Perfect-MongoDB`）
都是由 SwiftPM 自动解析的真实 `url:` 依赖——无需检出相邻的仓库。
