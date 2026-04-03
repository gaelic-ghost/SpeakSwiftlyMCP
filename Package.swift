// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftlyMCP",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .executable(name: "SpeakSwiftlyMCP", targets: ["SpeakSwiftlyMCP"]),
    ],
    dependencies: [
        .package(path: "../SpeakSwiftly"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpeakSwiftlyMCP",
            dependencies: [
                .product(name: "SpeakSwiftlyCore", package: "SpeakSwiftly"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyMCPTests",
            dependencies: [
                "SpeakSwiftlyMCP",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
