// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xnotifs-menubar",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "xnotifs-menubar",
            path: "Sources/xnotifs-menubar"
        )
    ]
)
