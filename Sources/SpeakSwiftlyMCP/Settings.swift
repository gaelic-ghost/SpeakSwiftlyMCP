import Foundation

// MARK: - Settings

struct ServerSettings: Sendable, Hashable {
    let host: String
    let port: Int
    let mcpPath: String
    let speakswiftlySourcePath: URL?
    let xcodeBuildConfiguration: String
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
            speakswiftlySourcePath: path("SPEAKSWIFTLY_SOURCE_PATH", default: repoRoot.deletingLastPathComponent().appendingPathComponent("SpeakSwiftly", isDirectory: true)),
            xcodeBuildConfiguration: value("XCODE_BUILD_CONFIGURATION") ?? "Debug",
            launchagentLabel: value("LAUNCHAGENT_LABEL") ?? "com.galew.speak-to-user-mcp",
            logDirectory: path("LOG_DIRECTORY", default: URL(fileURLWithPath: NSString(string: "~/Library/Logs/speak-to-user-mcp").expandingTildeInPath, isDirectory: true)) ?? URL(fileURLWithPath: NSString(string: "~/Library/Logs/speak-to-user-mcp").expandingTildeInPath, isDirectory: true),
            speakswiftlyProfileRoot: path("SPEAKSWIFTLY_PROFILE_ROOT")
        )
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
