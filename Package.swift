// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerfectSession",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "PerfectSessionCore",         targets: ["PerfectSessionCore"]),
        .library(name: "PerfectSessionMySQL",         targets: ["PerfectSessionMySQL"]),
        .library(name: "PerfectSessionPostgreSQL",    targets: ["PerfectSessionPostgreSQL"]),
        .library(name: "PerfectSessionRedis",         targets: ["PerfectSessionRedis"]),
        .library(name: "PerfectSessionSQLite",        targets: ["PerfectSessionSQLite"]),
        .library(name: "PerfectSessionMongoDB",       targets: ["PerfectSessionMongoDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-MySQL.git", branch: "main"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-PostgreSQL.git", branch: "main"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-Redis.git", branch: "main"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", branch: "main"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-MongoDB.git", from: "4.0.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PerfectSessionCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PerfectSessionMySQL",
            dependencies: [
                "PerfectSessionCore",
                .product(name: "PerfectMySQL", package: "Perfect-MySQL"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PerfectSessionPostgreSQL",
            dependencies: [
                "PerfectSessionCore",
                .product(name: "PerfectPostgreSQL", package: "Perfect-PostgreSQL"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PerfectSessionRedis",
            dependencies: [
                "PerfectSessionCore",
                .product(name: "PerfectRedis", package: "Perfect-Redis"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PerfectSessionSQLite",
            dependencies: [
                "PerfectSessionCore",
                .product(name: "PerfectSQLite", package: "Perfect-SQLite"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PerfectSessionMongoDB",
            dependencies: [
                "PerfectSessionCore",
                .product(name: "PerfectMongoDB", package: "Perfect-MongoDB"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionCoreTests",
            dependencies: ["PerfectSessionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionMySQLTests",
            dependencies: ["PerfectSessionMySQL"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionPostgreSQLTests",
            dependencies: ["PerfectSessionPostgreSQL"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionRedisTests",
            dependencies: ["PerfectSessionRedis"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionSQLiteTests",
            dependencies: ["PerfectSessionSQLite"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PerfectSessionMongoDBTests",
            dependencies: ["PerfectSessionMongoDB"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
