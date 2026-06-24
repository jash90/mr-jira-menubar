// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MRJiraMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MenuBarCore"),
        .executableTarget(name: "MRJiraMenuBar", dependencies: ["MenuBarCore"]),
        .testTarget(name: "MenuBarCoreTests", dependencies: ["MenuBarCore"]),
    ]
)
