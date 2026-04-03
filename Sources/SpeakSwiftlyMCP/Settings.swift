import Foundation

// MARK: - Settings

struct ServerSettings: Sendable, Hashable {
    let host: String
    let port: Int
    let mcpPath: String
    let speakswiftlyRuntimePath: URL?
    let speakswiftlySourcePath: URL?
    let xcodeBuildConfiguration: String
    let xcodeDerivedDataPath: URL
    let xcodeSourcePackagesPath: URL
    let buildMetadataPath: URL
    let launchagentLabel: String
    let logDirectory: URL
    let speakswiftlyProfileRoot: URL?

    static let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let prefix = "SPEAK_TO_USER_MCP_"

        func value(_ key: String) -> String? {
            environment[prefix + key]
        }

        func path(_ key: String, default defaultURL: URL? = nil) -> URL? {
            guard let raw = value(key), raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return defaultURL?.standardizedFileURL
            }
            return resolvePath(raw)
        }

        return .init(
            host: value("HOST") ?? "127.0.0.1",
            port: Int(value("PORT") ?? "") ?? 7341,
            mcpPath: normalizePath(value("MCP_PATH") ?? "/mcp"),
            speakswiftlyRuntimePath: path("SPEAKSWIFTLY_RUNTIME_PATH"),
            speakswiftlySourcePath: path("SPEAKSWIFTLY_SOURCE_PATH", default: repoRoot.deletingLastPathComponent().appendingPathComponent("SpeakSwiftly", isDirectory: true)),
            xcodeBuildConfiguration: value("XCODE_BUILD_CONFIGURATION") ?? "Debug",
            xcodeDerivedDataPath: path("XCODE_DERIVED_DATA_PATH", default: repoRoot.appendingPathComponent(".local/xcode/derived-data", isDirectory: true)) ?? repoRoot.appendingPathComponent(".local/xcode/derived-data", isDirectory: true),
            xcodeSourcePackagesPath: path("XCODE_SOURCE_PACKAGES_PATH", default: repoRoot.appendingPathComponent(".local/xcode/source-packages", isDirectory: true)) ?? repoRoot.appendingPathComponent(".local/xcode/source-packages", isDirectory: true),
            buildMetadataPath: path("BUILD_METADATA_PATH", default: repoRoot.appendingPathComponent(".local/xcode/SpeakSwiftly.build.json")) ?? repoRoot.appendingPathComponent(".local/xcode/SpeakSwiftly.build.json"),
            launchagentLabel: value("LAUNCHAGENT_LABEL") ?? "com.galew.speak-to-user-mcp",
            logDirectory: path("LOG_DIRECTORY", default: URL(fileURLWithPath: NSString(string: "~/Library/Logs/speak-to-user-mcp").expandingTildeInPath, isDirectory: true)) ?? URL(fileURLWithPath: NSString(string: "~/Library/Logs/speak-to-user-mcp").expandingTildeInPath, isDirectory: true),
            speakswiftlyProfileRoot: path("SPEAKSWIFTLY_PROFILE_ROOT")
        )
    }

    var cachedRuntimeProductsPath: URL {
        xcodeDerivedDataPath
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent(xcodeBuildConfiguration, isDirectory: true)
    }

    var cachedBinaryPath: URL {
        cachedRuntimeProductsPath.appendingPathComponent("SpeakSwiftly")
    }

    var cachedMetallibPath: URL {
        cachedRuntimeProductsPath
            .appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("default.metallib")
    }

    var packageDebugBinaryPath: URL? {
        speakswiftlySourcePath?
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("arm64-apple-macosx", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("SpeakSwiftly")
    }

    private static func normalizePath(_ raw: String) -> String {
        raw.hasPrefix("/") ? raw : "/" + raw
    }

    private static func resolvePath(_ raw: String) -> URL {
        let expanded = NSString(string: raw).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return repoRoot.appendingPathComponent(expanded).standardizedFileURL
    }
}
