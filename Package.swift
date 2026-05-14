// swift-tools-version: 6.0

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
        ),
        .testTarget(
            name: "OpenWorkNativeTests",
            dependencies: ["OpenWorkNative"],
            path: "Tests/OpenWorkNativeTests"
        )
    ]
)
