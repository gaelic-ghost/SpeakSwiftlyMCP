import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Deprecation Tests

@Test func deprecationMessagePointsToCombinedServer() {
    #expect(SpeakSwiftlyMCPDeprecation.replacementPackageName == "SpeakSwiftlyServer")
    #expect(SpeakSwiftlyMCPDeprecation.replacementReadmePath.contains("SpeakSwiftlyServer"))
    #expect(SpeakSwiftlyMCPDeprecation.message.contains("deprecated"))
    #expect(SpeakSwiftlyMCPDeprecation.message.contains("SpeakSwiftlyServer"))
}
