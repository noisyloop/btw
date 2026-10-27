// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "btw",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "btw", path: "Sources/btw")
    ]
)
