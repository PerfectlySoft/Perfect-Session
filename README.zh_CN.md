# Perfect Sessions（核心库） [English](README.md)

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

Perfect 的会话存储与会话安全基础组件，针对 Swift 6 与严格并发检查重写：包括会话模型、可插拔的存储后端，
以及不依赖具体 Web 框架的 CSRF、CORS、Cookie 与身份验证辅助功能。

本包把过去分散的 `Perfect-Session-MySQL`/`-PostgreSQL`/`-Redis`/`-SQLite`/`-MongoDB` 仓库**合并**为一个包，
每个后端对应一个产品；上述仓库均已被本包取代。`Perfect-Session-CouchDB` 没有被沿用。

完整说明（包括 Perfect-NIO 示例和迁移细节）以 [英文 README](README.md) 为准。

## 环境要求

- Swift 6.2 或更新版本（`swift-tools-version: 6.2`）。所有目标都在 Swift 6 语言模式下编译。
- macOS 12 或更新版本，或 Linux。CI 在 Ubuntu 24.04 上用 Swift 6.2 和 6.4 编译并测试（每个后端都连接真实服务器），
  并在 macOS 上用 Xcode 26.0.1 和 26.6 测试。
- 每个后端都需要对应数据库的客户端库，详见下方列表。

## 安装

``` swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-Session.git", from: "4.0.0"),
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

只有你所依赖的后端才会被编译：只使用 MySQL 后端的应用既不会编译其他后端，也不需要它们的库。

## 核心库

`PerfectSessionCore` 不依赖任何外部数据库。它提供：

- `PerfectSession`：会话值（令牌、用户 ID、时间戳、`data`、CSRF 令牌、`isExpired()`，以及检查过期和可选的
  IP/用户代理绑定的 `isValid()`）；
- `SessionConfig`：Cookie、过期、CSRF 与 CORS 设置；
- `SessionDriver` 协议和 `MemorySessionDriver`，后者是用于开发和测试的进程内存储；
- `SessionCookie`：根据 `SessionConfig` 生成会话 Cookie 的 `Set-Cookie` 值；
- `AuthFilter`（路径包含/排除规则），以及 `CSRFSecurity`/`CORSSecurity`（对请求头字符串进行来源和主机检查）。

这些组件不依赖任何 HTTP 框架。`SessionDriver` 是一个 `async` 协议：`create`、`resume`（同时会 `throws`）、`save`、
`destroy`、`regenerate`、`clean` 和 `setup`。驱动遵循 `Sendable`，同一个驱动实例可以在多个请求之间共享。

### 会话安全

- **令牌**：会话令牌和 CSRF 令牌取自系统的安全随机数生成器（32 字节，64 个十六进制字符）。
- **过期由服务器强制执行**：会话空闲超过 `idle` 秒（所有驱动的 `save` 都会续期），或设置了
  `SessionConfig.absoluteTimeout` 且自创建起已超过该秒数时，所有驱动的 `resume` 都会抛出 `InvalidSessionError`。
  时间以 1970 年以来的秒数存储，与进程时区无关。
- **会话固定**：`resume` 只返回驱动已存储的会话，`save` 只更新已存储的会话。用户登录或权限变化时调用
  `regenerate(_:)`，并把新令牌发给客户端。
- **Cookie**：`SessionCookie.setCookie(token:)` 与 `expiredCookie()` 使用 `SessionConfig` 的 Cookie 设置
  （默认 `HttpOnly`、`SameSite=Strict`）；`SameSite=None` 和 `__Secure-`/`__Host-` 前缀总会加上 `Secure`。
- **CSRF**：用 `CSRFSecurity.tokenMatches(_:_:)` 比较请求带回的令牌与 `data["csrf"]`，并用
  `CSRFSecurity.isValid(origin:host:)` 检查 `Origin`（比较协议、主机和端口，忽略大小写和默认端口）。
- **需要登录的路径**：`AuthFilter.requiresAuthentication(_:using:)` 按 `/` 分段、默认忽略大小写进行匹配；
  `"/admin"` 覆盖其下所有路径但不覆盖 `/administrator`。`shouldWeAccept` 已弃用。
- **会话数据**以 JSON 存储，`data` 只能存放 JSON 值；无法存为 JSON 的键不会被保存（只记录键名），其他键和 CSRF
  令牌照常保存。日志中只记录令牌的 SHA-256 前缀（`PerfectSession.logID`），不记录令牌本身。
- **配置**是全局状态，请在启动时设置一次，然后再开始处理请求。

## 存储后端

| 产品 | 依赖 | 需要 |
|---|---|---|
| `PerfectSessionMySQL` | [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) 4 | MySQL 客户端库（`libmysqlclient`） |
| `PerfectSessionPostgreSQL` | [Perfect-PostgreSQL](https://github.com/PerfectlySoft/Perfect-PostgreSQL) 5 | `libpq` |
| `PerfectSessionRedis` | [Perfect-Redis](https://github.com/PerfectlySoft/Perfect-Redis) 4、`swift-log` | — |
| `PerfectSessionSQLite` | [Perfect-SQLite](https://github.com/PerfectlySoft/Perfect-SQLite) 6、`swift-log` | Linux 上需要 `libsqlite3-dev` |
| `PerfectSessionMongoDB` | [Perfect-MongoDB](https://github.com/PerfectlySoft/Perfect-MongoDB) 4、`swift-log` | libmongoc 2（[环境要求](https://github.com/PerfectlySoft/Perfect-MongoDB#requirements)） |

**MySQL、PostgreSQL 与 SQLite** 后端每个会话一行，所有值都以参数绑定；`created`、`updated`、`idle` 为 64 位列。
**Redis** 后端把会话以 JSON 存在 `RedisSessionConnector.keyPrefix`（默认 `perfect-session:`）加令牌的键下，
TTL 为会话的 `idle`；`RedisSessionConnector.commandTimeout`（默认 5 秒，设为 nil 则不限）会传给 Perfect-Redis，超时的调用会抛出错误并关闭连接。
**MongoDB** 后端每个会话一个文档，`data` 为子文档，`setup()` 会添加 TTL 索引；`data` 中的空键、`%` 和 NUL 会被转义。

### 从 Perfect-Session-MongoDB 迁移

已归档的 `Perfect-Session-MongoDB` 的文档无法被新后端读取，切换后现有会话都会结束。如果新驱动使用旧集合，
`setup()` 会删除这些旧文档（`token` 与 `data` 为字符串、含 `created`/`updated`/`idle` 且没有 `expiresAt`）。
如想保留旧文档，请使用另一个 `collection`。

## 运行测试

各后端的实时测试在对应开关为 `1` 时运行：`MYSQL_TESTS`（还需 `MYSQL_PORT`）、`PG_TESTS`、`REDIS_TESTS`、
`MONGODB_TESTS`、`SQLITE_TESTS`；连接变量见英文 README。设置 `SESSION_REQUIRE_LIVE=1`（CI 中如此）时，
未开启或无法连接服务器的后端会导致测试失败，而不是跳过。

## 迁移

从 3.x 迁移：模块与 HTTP 过滤器已被替换，驱动改为 `async`，需要自己编写中间件。从 4.0.0 之前的 `main` 迁移：
过期会话会被拒绝、Redis 键加了前缀、令牌改为 64 个十六进制字符、旧表需要把时间列改为 64 位。详见英文 README 的
“Migrating from earlier versions”一节。

## 旧版本

本包在 Swift 6 之前的代码（3.1.5 加上之后的 OAuth2 标志）保留在 [`legacy`](../../tree/legacy) 分支上。
