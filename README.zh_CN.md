# Perfect Sessions（核心库） [English](README.md)

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

Perfect 的会话存储与会话安全基础组件，针对 Swift 6 与严格并发检查重写：包括会话模型、可插拔的存储后端，
以及不依赖具体 Web 框架的 CSRF、CORS 与身份验证检查。

本包把过去分散的 `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`/`-MongoDB` 仓库**合并**为一个包，
每个后端对应一个产品；上述仓库均已被本包取代。`Perfect-Session-CouchDB` 没有被沿用。

## 环境要求

- Swift 6.2 或更新版本（`swift-tools-version: 6.2`）。所有目标都在 Swift 6 语言模式下编译。
- macOS 12 或更新版本，或 Linux。所有后端都可以在 Linux 上编译（已用 Ubuntu 26.04 上的 Swift 6.4 测试）。
- 每个后端都需要对应数据库的客户端库，详见下方列表。

## 构建

把它加入你的 `Package.swift`，并加上你需要的后端：

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

Swift 6 版本尚未发布带标签的正式版本，因此请依赖 `main` 分支。`3.x` 标签是重写之前的版本。只有你所依赖的后端
才会被编译：只使用 MySQL 后端的应用既不会编译其他后端，也不需要它们的库。

`PerfectSessionCore` 不依赖任何外部数据库。它提供：

- `PerfectSession`：会话值（令牌、用户 ID、时间戳、`data`、CSRF 令牌，以及用于检查过期和可选的 IP/用户代理
  绑定的 `isValid()`）；
- `SessionConfig`：Cookie、过期、CSRF 与 CORS 设置；
- `SessionDriver` 协议和 `MemorySessionDriver`，后者是用于开发和测试的进程内存储；
- `AuthFilter`（路径包含/排除规则），以及 `CSRFSecurity`/`CORSSecurity`（对请求头字符串进行来源和主机检查）。

这些组件不依赖任何 HTTP 框架。由你的服务器中间件读取会话 Cookie、调用驱动（`create`、`resume`、`save`、
`destroy`），并执行 CSRF、CORS 与身份验证检查。

`SessionDriver` 是一个 `async` 协议：`create`、`resume`（同时会 `throws`）、`save`、`destroy`、`clean` 和
`setup`。驱动遵循 `Sendable`，因此同一个驱动实例可以在多个请求之间共享。

## 存储后端

每个后端都是本包中的一个目标和产品，并有各自的测试套件。通过对应的 `…SessionConnector` 类型配置后端。测试默认
会跳过，除非把表中所示的开关设为 `1`，并设置该测试文件中的连接变量。

| 产品 | 依赖 | 需要 | 测试 |
|---|---|---|---|
| `PerfectSessionMySQL` | [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) | MySQL 客户端库（`libmysqlclient`） | `MYSQL_TESTS` |
| `PerfectSessionPostgreSQL` | [Perfect-PostgreSQL](https://github.com/PerfectlySoft/Perfect-PostgreSQL) | `libpq` | `PG_TESTS` |
| `PerfectSessionRedis` | [Perfect-Redis](https://github.com/PerfectlySoft/Perfect-Redis)、`swift-log` | — | `REDIS_TESTS` |
| `PerfectSessionSQLite` | [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite)、`swift-log` | macOS、Linux（Linux 上需要 `libsqlite3-dev`） | `SQLITE_TESTS` |
| `PerfectSessionMongoDB` | [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4.x、`swift-log` | libmongoc 2（[环境要求](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)） | `MONGODB_TESTS` |

**MongoDB** 后端把每个会话存储为一个以其令牌为键的文档，`data` 以子文档形式存储。它的 `setup()` 会添加 TTL
索引，让 MongoDB 自动删除过期会话。除了 `MongoDBSessionConnector`（`uri`、`database`、`collection`）之外，
你也可以向其初始化方法传入 URI 或现有的 `MongoClientPool`。
`save` 只会更新仍然存在的会话，因此与注销同时发生的保存不会让会话复活；从未存储成功（其 `create` 失败）或已经过期的
会话，`save` 也不会再存储。libmongoc 拒绝空键，而键会在 NUL 处被截断，因此 `data` 中各层的键都会被转义：`%`
存为 `%25`，NUL 存为 `%00`，空键存为 `%`。其他键原样存储，因此 `data.role` 之类的查询照常可用。

### 从 Perfect-Session-MongoDB 迁移

已归档的 `Perfect-Session-MongoDB` 把每个会话存储在它自己的 `_id` 下，令牌放在 `token` 字段中，`data` 是 JSON
文本，并且没有过期时间。MongoDB 后端无法读取这些文档，因此切换后现有会话都会结束，用户需要重新登录。TTL 索引也
永远不会删除它们，所以如果你让新驱动使用旧的集合，`setup()` 会删除这些文档：即 `token` 为字符串、`data` 为字符串、
含有 `created`、`updated` 和 `idle` 字段且没有 `expiresAt` 的文档。等不再有旧实例写入该集合后，再运行一次
`setup()`。如果想保留旧文档，请使用另一个 `collection`。

## 更多信息

本包在 Swift 6 之前的版本保留在 [`legacy`](../../tree/legacy) 分支上。
