// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PureValet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PureValet",
            path: "Sources/PureValet"
        ),
        .testTarget(
            name: "PureValetTests",
            dependencies: ["PureValet"],
            path: "Tests/PureValetTests"
        ),
    ]
)
