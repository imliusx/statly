// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Statly",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Statly", dependencies: ["StatlyKit"]),
        .target(name: "StatlyKit"),
        .testTarget(name: "StatlyKitTests", dependencies: ["StatlyKit"]),
    ]
)
