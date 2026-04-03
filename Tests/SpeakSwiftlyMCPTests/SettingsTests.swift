import Foundation
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Settings Tests

@Test
func settingsNormalizeRelativePathsAndRoutePrefix() {
    let settings = ServerSettings.fromEnvironment(
        [
            "SPEAK_TO_USER_MCP_PORT": "7450",
            "SPEAK_TO_USER_MCP_MCP_PATH": "mcp",
            "SPEAK_TO_USER_MCP_SPEAKSWIFTLY_RUNTIME_PATH": "./runtime",
            "SPEAK_TO_USER_MCP_XCODE_DERIVED_DATA_PATH": "./.local/xcode/derived-data",
        ]
    )

    #expect(settings.port == 7450)
    #expect(settings.mcpPath == "/mcp")
    #expect(settings.speakswiftlyRuntimePath == ServerSettings.repoRoot.appendingPathComponent("runtime"))
    #expect(settings.xcodeDerivedDataPath == ServerSettings.repoRoot.appendingPathComponent(".local/xcode/derived-data"))
    #expect(settings.cachedBinaryPath.path.hasSuffix("/Build/Products/Debug/SpeakSwiftly"))
}

@Test
func settingsDefaultToAdjacentSpeakSwiftlyCheckout() {
    let settings = ServerSettings.fromEnvironment([:])
    #expect(settings.speakswiftlySourcePath?.lastPathComponent == "SpeakSwiftly")
}
