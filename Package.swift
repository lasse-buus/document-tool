// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocumentTool",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DocumentTool",
            path: "Sources/DocumentTool"
        )
    ]
)
