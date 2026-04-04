import Foundation
import Logging
import MCP
import SpeakSwiftlyCore
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Surface Tests

@Test
func mirroredToolPromptAndResourceNamesStayStable() {
    #expect(MCPTools.toolNames == [
        "queue_speech_live",
        "create_profile",
        "list_profiles",
        "remove_profile",
        "list_queue_generation",
        "list_queue_playback",
        "playback_pause",
        "playback_resume",
        "playback_state",
        "clear_queue",
        "cancel_request",
        "status",
    ])

    #expect(MCPPromptsCatalog.promptNames == [
        "draft_profile_voice_description",
        "draft_profile_source_text",
        "draft_voice_design_instruction",
        "draft_queue_playback_notice",
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

    let summary = try JSONDecoder().decode(SpeakSwiftlyMCP.ProfileSummary.self, from: Data(json.utf8))
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

@Test
func serverMetadataMatchesCurrentSwiftHostContract() async {
    let owner = SpeakSwiftlyOwner(
        settings: .fromEnvironment([:]),
        logger: Logger(label: "SpeakSwiftlyMCPTests"),
        makeRuntime: { FatalRuntime() }
    )
    let server = await MCPServerFactory.buildServer(
        settings: .fromEnvironment([:]),
        owner: owner,
        logger: Logger(label: "SpeakSwiftlyMCPTests")
    )

    #expect(server.name == "speak-to-user-mcp")
    #expect(server.version == "0.3.0")
    #expect(server.instructions?.contains("queue-based speech and playback-control tools") == true)
    #expect(
        MCPTools.definitions.first(where: { $0.name == "queue_speech_live" })?.description
        == "Queue live speech playback with a stored SpeakSwiftly profile and return once SpeakSwiftly has accepted the playback job."
    )
}

private struct FatalRuntime: SpeakSwiftlyRuntimeClient {
    func runtimeStatusEvents() async -> AsyncStream<SpeakSwiftlyCore.WorkerStatusEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func runtimeQueueSpeechHandle(text: String, profileName: String, jobType: SpeakSwiftlyCore.SpeechJobType, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeCreateProfileHandle(profileName: String, text: String, voiceDescription: String, outputPath: String?, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeListProfilesHandle(id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeRemoveProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeListQueueHandle(_ queueType: SpeakSwiftlyCore.WorkerQueueType, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimePlaybackHandle(_ action: SpeakSwiftlyCore.PlaybackAction, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeClearQueueHandle(id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeCancelRequestHandle(requestID: String, id: String) async -> RuntimeRequestHandle { fatalUnsupported() }

    func runtimeStart() async {}

    func runtimeShutdown() async {}

    private func fatalUnsupported() -> RuntimeRequestHandle {
        fatalError("Surface metadata test should not submit runtime requests.")
    }
}
