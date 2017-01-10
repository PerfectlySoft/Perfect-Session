// Generated automatically by Perfect Assistant Application
// Date: 2016-12-14 18:10:35 +0000
import PackageDescription
let package = Package(
    name: "PerfectSession",
    targets: [
		Target(
			name: "PerfectSession",
			dependencies: [.Target(name: "TurnstileCrypto")]),
		Target(
			name: "TurnstileCrypto"),
		],
    dependencies: [
		.Package(url: "https://github.com/PerfectlySoft/PerfectLib.git", majorVersion: 2),
		.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTP.git", majorVersion: 2),
		.Package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", majorVersion: 1),
	]
)
