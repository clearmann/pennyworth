// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pennyworth",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Pennyworth", resources: [.process("Resources")]),
        .testTarget(
            name: "PennyworthTests",
            dependencies: ["Pennyworth"]
        ),
    ]
)
