import Foundation
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Surface Tests

@Test
func mirroredToolPromptAndResourceNamesStayStable() {
    #expect(MCPTools.toolNames == [
        "speak_live",
        "speak_live_background",
        "create_profile",
        "list_profiles",
        "remove_profile",
        "status",
    ])

    #expect(MCPPromptsCatalog.promptNames == [
        "draft_profile_voice_description",
        "draft_profile_source_text",
        "draft_voice_design_instruction",
        "draft_background_playback_notice",
    ])

    #expect(Set(MCPResourcesCatalog.resources.map(\.uri)) == [
        "speak://status",
        "speak://profiles",
        "speak://playback-jobs",
        "speak://runtime",
    ])

    #expect(Set(MCPResourcesCatalog.templates.map(\.uriTemplate)) == [
        "speak://profiles/{profile_name}/detail",
        "speak://playback-jobs/{playback_job_id}",
    ])
}

@Test
func profileSummaryNormalizesSwiftReferenceDateTimestamps() throws {
    let json = """
    {
      "profile_name": "default-femme",
      "created_at": 796786212,
      "voice_description": "Warm narrator",
      "source_text": "Hello there"
    }
    """

    let summary = try JSONDecoder().decode(ProfileSummary.self, from: Data(json.utf8))
    #expect(summary.createdAt == "2026-04-02T01:30:12Z")
}
