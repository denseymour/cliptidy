// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipTidy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipTidy",
            path: "Sources/ClipTidy"
        )
    ]
)
