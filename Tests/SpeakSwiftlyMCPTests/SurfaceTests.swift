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

@Test
func statusResourceEncodingMatchesPythonSafeSummaryShape() throws {
    let payload = StatusResource(
        serverMode: "ready",
        workerMode: "ready",
        profileCacheState: "fresh",
        buildMetadataBuiltAt: nil,
        buildMetadataSourceTreeFingerprint: nil,
        currentSourceTreeFingerprint: nil,
        runtimeCacheState: "not_applicable",
        runtimeCacheWarning: nil,
        workerFailureSummary: nil,
        profileCacheWarning: nil,
        lastWorkerEvent: "resident_model_ready",
        lastWarningEvent: nil,
        recentWorkerErrorCount: 0,
        recentWorkerWarningCount: 0,
        lastProfileRefreshAt: nil
    )

    let object = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(payload)
    ) as? [String: Any]

    #expect(object?["worker_mode"] as? String == "ready")
    #expect(object?["runtime_cache_state"] as? String == "not_applicable")
    #expect(object?["last_worker_event"] as? String == "resident_model_ready")
    #expect(object?["runtime_products_path"] == nil)
    #expect(object?["worker_binary_path"] == nil)
}

@Test
func runtimeResourceEncodingMatchesPythonRuntimeSummaryShape() throws {
    let payload = RuntimeResource(
        host: "127.0.0.1",
        port: 7341,
        mcpPath: "/mcp",
        xcodeBuildConfiguration: "Debug",
        customProfileRootConfigured: true
    )

    let object = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(payload)
    ) as? [String: Any]

    #expect(object?["host"] as? String == "127.0.0.1")
    #expect(object?["port"] as? Int == 7341)
    #expect(object?["mcp_path"] as? String == "/mcp")
    #expect(object?["xcode_build_configuration"] as? String == "Debug")
    #expect(object?["custom_profile_root_configured"] as? Bool == true)
}
