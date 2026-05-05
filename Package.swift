// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenWorkNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenWorkNative", targets: ["OpenWorkNative"])
    ],
    targets: [
        .executableTarget(
            name: "OpenWorkNative",
            path: "Sources/OpenWorkNative"
        )
    ]
)
