// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ValetDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ValetDesktop",
            path: "Sources/ValetDesktop"
        ),
        .testTarget(
            name: "ValetDesktopTests",
            dependencies: ["ValetDesktop"],
            path: "Tests/ValetDesktopTests"
        ),
    ]
)
