// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenWorkNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenWorkNative", targets: ["OpenWorkNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .executableTarget(
            name: "OpenWorkNative",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/OpenWorkNative"
        ),
        .testTarget(
            name: "OpenWorkNativeTests",
            dependencies: ["OpenWorkNative"],
            path: "Tests/OpenWorkNativeTests"
        )
    ]
)
