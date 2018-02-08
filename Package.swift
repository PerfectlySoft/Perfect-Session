// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "PerfectSession",
    products: [
        .library(
            name: "PerfectSession",
            targets: ["PerfectSession"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", from: "3.0.5"),
    ],
    targets: [
        .target(
            name: "PerfectSession",
            dependencies: ["PerfectLogger"]),
        .testTarget(
            name: "PerfectSessionTests",
            dependencies: ["PerfectSession"]),
    ]
)
