// swift-tools-version:5.9
import PackageDescription
import Foundation

// 测试目录不入库，仅在本地存在时才声明测试 target —— 否则克隆者连 swift build 都会失败
let hasTests = FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Tests/StatlyKitTests").path
)

var targets: [Target] = [
    .executableTarget(name: "Statly", dependencies: ["StatlyKit"]),
    .target(name: "StatlyKit"),
]
if hasTests {
    targets.append(.testTarget(name: "StatlyKitTests", dependencies: ["StatlyKit"]))
}

let package = Package(
    name: "Statly",
    platforms: [.macOS(.v13)],
    targets: targets
)
