// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pennyworth",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Pennyworth"),
        .testTarget(name: "PennyworthTests", dependencies: ["Pennyworth"]),
    ]
)
