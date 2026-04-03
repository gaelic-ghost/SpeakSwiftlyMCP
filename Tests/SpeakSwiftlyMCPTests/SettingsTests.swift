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
            "SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH": "./SpeakSwiftly",
            "SPEAK_TO_USER_MCP_LOG_DIRECTORY": "./.local/logs",
        ]
    )

    #expect(settings.port == 7450)
    #expect(settings.mcpPath == "/mcp")
    #expect(settings.speakswiftlySourcePath == ServerSettings.repoRoot.appendingPathComponent("SpeakSwiftly"))
    #expect(settings.logDirectory == ServerSettings.repoRoot.appendingPathComponent(".local/logs"))
}

@Test
func settingsDefaultToAdjacentSpeakSwiftlyCheckout() {
    let settings = ServerSettings.fromEnvironment([:])
    #expect(settings.speakswiftlySourcePath?.lastPathComponent == "SpeakSwiftly")
}
