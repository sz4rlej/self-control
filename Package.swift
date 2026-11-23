// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SelfControl",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SelfControlCore"),
        .executableTarget(name: "selfcontrold", dependencies: ["SelfControlCore"]),
        .executableTarget(name: "SelfControlApp", dependencies: ["SelfControlCore"]),
        .testTarget(name: "SelfControlCoreTests", dependencies: ["SelfControlCore"]),
    ],
    swiftLanguageModes: [.v5]
)
