import Foundation
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Model Tests

@Test
func jsonScalarRoundTripsAcrossSupportedPrimitiveTypes() throws {
    let payload: [String: JSONScalar] = [
        "name": .string("default-femme"),
        "attempts": .int(2),
        "temperature": .double(0.65),
        "enabled": .bool(true),
    ]

    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode([String: JSONScalar].self, from: data)

    #expect(decoded == payload)
    #expect(decoded["name"]?.stringValue == "default-femme")
    #expect(decoded["attempts"]?.stringValue == nil)
}

@Test
func profileSummaryAcceptsStringCreatedAtAndRejectsUnreadableValues() throws {
    let stringJSON = """
    {
      "profile_name": "default-femme",
      "created_at": "2026-04-02T01:30:12Z",
      "voice_description": "Warm narrator",
      "source_text": "Hello there"
    }
    """

    let summary = try JSONDecoder().decode(ProfileSummary.self, from: Data(stringJSON.utf8))
    #expect(summary.createdAt == "2026-04-02T01:30:12Z")

    let invalidJSON = """
    {
      "profile_name": "default-femme",
      "created_at": true,
      "voice_description": "Warm narrator",
      "source_text": "Hello there"
    }
    """

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ProfileSummary.self, from: Data(invalidJSON.utf8))
    }
}

@Test
func workerLogEventDecodesSnakeCaseFieldsAndMixedDetailScalars() throws {
    let json = """
    {
      "event": "request_failed",
      "level": "error",
      "ts": "2026-04-02T01:30:12Z",
      "request_id": "req-123",
      "op": "speak_live",
      "profile_name": "default-femme",
      "queue_depth": 1,
      "elapsed_ms": 42,
      "details": {
        "message": "Playback device disappeared",
        "retryable": false,
        "attempt": 3,
        "latency_ms": 12.5
      }
    }
    """

    let event = try JSONDecoder().decode(WorkerLogEvent.self, from: Data(json.utf8))

    #expect(event.requestID == "req-123")
    #expect(event.profileName == "default-femme")
    #expect(event.queueDepth == 1)
    #expect(event.elapsedMS == 42)
    #expect(event.details?["message"]?.stringValue == "Playback device disappeared")
    #expect(event.details?["retryable"] == .bool(false))
    #expect(event.details?["attempt"] == .int(3))
    #expect(event.details?["latency_ms"] == .double(12.5))
}

@Test
func profileAndPlaybackResourcesEncodeSnakeCaseFields() throws {
    let profile = ProfileMetadataResource(
        profileName: "default-femme",
        createdAt: "2026-04-02T01:30:12Z"
    )
    let playback = PlaybackJobResource(
        playbackJobID: "playback-123",
        profileName: "default-femme",
        playbackState: "completed",
        acceptedAt: "2026-04-02T01:30:10Z",
        launchedAt: "2026-04-02T01:30:11Z",
        completedAt: "2026-04-02T01:30:12Z",
        launchStage: "starting_playback",
        lastStage: "completed",
        textPreview: "Hello there",
        errorMessage: nil
    )

    let profileObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(profile)
    ) as? [String: Any]
    let playbackObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(playback)
    ) as? [String: Any]

    #expect(profileObject?["profile_name"] as? String == "default-femme")
    #expect(profileObject?["created_at"] as? String == "2026-04-02T01:30:12Z")
    #expect(playbackObject?["playback_job_id"] as? String == "playback-123")
    #expect(playbackObject?["profile_name"] as? String == "default-femme")
    #expect(playbackObject?["playback_state"] as? String == "completed")
    #expect(playbackObject?["text_preview"] as? String == "Hello there")
}

@Test
func queueResultsEncodeSnakeCaseFields() throws {
    let list = ListQueueResult(
        id: "req-list",
        ok: true,
        activeRequest: ActiveRequestSummary(
            id: "req-active",
            op: "speak_live",
            profileName: "default-femme"
        ),
        queue: [
            QueuedRequestSummary(
                id: "req-queued",
                op: "create_profile",
                profileName: "bright-guide",
                queuePosition: 1
            )
        ]
    )
    let clear = ClearQueueResult(id: "req-clear", ok: true, clearedCount: 2)
    let cancel = CancelRequestResult(
        id: "req-cancel",
        ok: true,
        cancelledRequestID: "req-queued"
    )

    let listObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(list)
    ) as? [String: Any]
    let clearObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(clear)
    ) as? [String: Any]
    let cancelObject = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(cancel)
    ) as? [String: Any]

    let activeRequest = listObject?["active_request"] as? [String: Any]
    let queue = listObject?["queue"] as? [[String: Any]]

    #expect(activeRequest?["profile_name"] as? String == "default-femme")
    #expect(queue?.first?["queue_position"] as? Int == 1)
    #expect(queue?.first?["profile_name"] as? String == "bright-guide")
    #expect(clearObject?["cleared_count"] as? Int == 2)
    #expect(cancelObject?["cancelled_request_id"] as? String == "req-queued")
}
