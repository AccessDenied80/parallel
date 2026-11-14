// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Parallel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Parallel", path: "Sources/Parallel")
    ]
)
