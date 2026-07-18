// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "manga",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "manga",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
