// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageGen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ImageGen",
            path: "Sources/ImageGen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
