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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SpeakSwiftlyMCP",
            dependencies: [],
            exclude: [
                "HTTPBridge.swift",
                "MCPServerFactory.swift",
                "MCPSurface.swift",
                "Models.swift",
                "Settings.swift",
                "SpeakSwiftlyOwner.swift",
            ],
            sources: [
                "Main.swift",
                "Deprecation.swift",
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyMCPTests",
            dependencies: [
                "SpeakSwiftlyMCP",
            ],
            exclude: [
                "E2ETests.swift",
                "ModelsTests.swift",
                "OwnerTests.swift",
                "SettingsTests.swift",
                "SurfaceTests.swift",
            ],
            sources: [
                "DeprecationTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
