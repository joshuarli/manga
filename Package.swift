// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "manga",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "manga",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "mangaTests",
            dependencies: ["manga"]
        )
    ]
)
