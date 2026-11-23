// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SelfControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SelfControlCore"),
        .executableTarget(name: "selfcontrold", dependencies: ["SelfControlCore"]),
        .executableTarget(name: "SelfControlApp", dependencies: ["SelfControlCore"]),
        .testTarget(name: "SelfControlCoreTests", dependencies: ["SelfControlCore"]),
    ]
)
