import Foundation
import Logging
import SpeakSwiftlyCore
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - Owner Tests

@Test
func initializeCachesProfilesFromRuntime() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(timeIntervalSince1970: 1_775_000_000),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        default:
            Issue.record("Unexpected request during initialize: \(request.opName)")
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)

    await owner.initialize()

    let status = await owner.status()
    #expect(status.workerMode == "ready")
    #expect(status.profileCacheState == "fresh")
    #expect(status.cachedProfiles.count == 1)
    #expect(await owner.cachedProfile("default-femme")?.voiceDescription == "Warm narrator")
}

@Test
func initializeDegradesWhenProfileRefreshPayloadIsMissing() async {
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id))]
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)

    await owner.initialize()

    let status = await owner.status()
    #expect(status.serverMode == "degraded")
    #expect(status.workerMode == "failed")
    #expect(status.profileCacheState == "uninitialized")
    #expect(status.workerFailureSummary?.contains("list_profiles without returning the profile list") == true)
}

@Test
func speakLiveBackgroundTracksCompletionAndRetainsRecentJobsOnly() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        case .speakLiveBackground(let id, _, _):
            return runtimeHandle(
                id: id,
                request: request,
                events: [
                    .acknowledged(.init(id: id)),
                    .progress(.init(id: id, stage: .startingPlayback)),
                    .progress(.init(id: id, stage: .playbackFinished)),
                    .completed(.init(id: id)),
                ]
            )
        default:
            Issue.record("Unexpected request during background playback test: \(request.opName)")
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    var firstPlaybackJobID: String?
    for index in 0..<21 {
        let result = try await owner.speakLiveBackground(
            text: "Message \(index) " + String(repeating: "x", count: 120),
            profileName: "default-femme"
        )
        if firstPlaybackJobID == nil {
            firstPlaybackJobID = result.playbackJobID
        }
    }

    await eventually {
        await owner.playbackJobs().allSatisfy { $0.playbackState == "completed" }
    }

    let jobs = await owner.playbackJobs()
    #expect(jobs.count == 20)
    #expect(firstPlaybackJobID != nil)
    #expect(await owner.playbackJob(firstPlaybackJobID!) == nil)

    let newestJob = try #require(jobs.last)
    #expect(newestJob.launchStage == WorkerProgressStage.startingPlayback.rawValue)
    #expect(newestJob.lastStage == "completed")
    #expect(newestJob.completedAt != nil)
    #expect(newestJob.textPreview.hasSuffix("..."))
}

@Test
func speakLiveForwardsMappedProgressEvents() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        case .speakLive(let id, _, _):
            return runtimeHandle(
                id: id,
                request: request,
                events: [
                    .queued(.init(id: id, reason: .waitingForActiveRequest, queuePosition: 1)),
                    .started(.init(id: id, op: request.opName)),
                    .progress(.init(id: id, stage: .bufferingAudio)),
                    .completed(.init(id: id)),
                ]
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    let events = EventRecorder()
    let result = try await owner.speakLive(
        text: "Hello there",
        profileName: "default-femme",
        onEvent: { await events.record($0) }
    )

    #expect(result.ok)
    let recorded = await events.snapshot()
    #expect(recorded.map(\.event).compactMap { $0 } == ["queued", "started", "progress"])
    #expect(recorded.first?.reason == WorkerQueuedReason.waitingForActiveRequest.rawValue)
    #expect(recorded[1].op == "speak_live")
    #expect(recorded[2].stage == WorkerProgressStage.bufferingAudio.rawValue)
    #expect(recorded.last?.ok == true)
}

@Test
func createProfileRejectsMissingResultFieldsClearly() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        case .createProfile(let id, _, _, _, _):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id))]
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    do {
        _ = try await owner.createProfile(
            profileName: "new-profile",
            text: "Hello there",
            voiceDescription: "Soft and warm",
            outputPath: nil
        )
        Issue.record("Expected createProfile to reject a completion payload without profile metadata.")
    } catch let error as SpeakSwiftlyOwnerError {
        #expect(error.errorDescription?.contains("without returning the profile name and profile path") == true)
    }
}

@Test
func statusObservationUpdatesFailureStateFromRuntimeEvents() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    await runtime.emitStatus(.init(stage: .residentModelFailed))

    await eventually {
        await owner.status().workerMode == "failed"
    }

    let status = await owner.status()
    #expect(status.workerFailureSummary == "SpeakSwiftly reported that its resident model failed to load.")
    #expect(status.workerDiagnostics.lastEvent == "worker_status")
    #expect(status.workerDiagnostics.recentErrorCount == 1)
}

@Test
func speakLiveBeforeInitializationReturnsHelpfulUnavailableError() async {
    let runtime = FakeRuntime { request in
        runtimeHandle(id: request.id, request: request, events: [])
    }
    let owner = makeOwner(runtime: runtime)

    do {
        _ = try await owner.speakLive(text: "Hello there", profileName: "default-femme")
        Issue.record("Expected speakLive to fail before runtime initialization.")
    } catch let error as SpeakSwiftlyOwnerError {
        #expect(error.errorDescription?.contains("not ready yet") == true)
    } catch {
        Issue.record("Expected a SpeakSwiftlyOwnerError before initialization, but received: \(error.localizedDescription)")
    }
}

@Test
func speakLiveMapsWorkerErrorsIntoReadableRequestFailures() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        case .speakLive:
            return runtimeThrowingHandle(
                id: request.id,
                request: request,
                error: WorkerError(
                    code: .audioPlaybackFailed,
                    message: "SpeakSwiftly could not hand audio to the selected playback device."
                )
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    do {
        _ = try await owner.speakLive(text: "Hello there", profileName: "default-femme")
        Issue.record("Expected speakLive to surface a runtime request rejection.")
    } catch let error as SpeakSwiftlyOwnerError {
        #expect(error.errorDescription == "SpeakSwiftly could not hand audio to the selected playback device.")
    }

    let status = await owner.status()
    #expect(status.workerDiagnostics.lastErrorMessage == "SpeakSwiftly could not hand audio to the selected playback device.")
    #expect(status.workerDiagnostics.recentErrorCount == 1)
}

@Test
func speakLiveBackgroundMarksFailedJobsWhenStreamingBreaks() async throws {
    let profile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime { request in
        switch request {
        case .listProfiles(let id):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: [profile]))]
            )
        case .speakLiveBackground:
            return runtimeThrowingHandle(
                id: request.id,
                request: request,
                prefixEvents: [
                    .acknowledged(.init(id: request.id)),
                    .progress(.init(id: request.id, stage: .startingPlayback)),
                ],
                error: WorkerError(
                    code: .audioPlaybackFailed,
                    message: "SpeakSwiftly lost the playback device while the background job was running."
                )
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    let result = try await owner.speakLiveBackground(
        text: "Hello there",
        profileName: "default-femme"
    )

    await eventually {
        await owner.playbackJob(result.playbackJobID)?.playbackState == "failed"
    }

    let job = try #require(await owner.playbackJob(result.playbackJobID))
    #expect(job.launchStage == WorkerProgressStage.startingPlayback.rawValue)
    #expect(job.playbackState == "failed")
    #expect(job.errorMessage?.contains("SpeakSwiftlyCore.WorkerError") == true)
}

@Test
func removeProfileFallsBackToRequestedNameWhenWorkerOmitsIt() async throws {
    let initialProfile = SpeakSwiftlyCore.ProfileSummary(
        profileName: "default-femme",
        createdAt: Date(),
        voiceDescription: "Warm narrator",
        sourceText: "Hello there"
    )
    let runtime = FakeRuntime(
        profileSnapshots: [
            [initialProfile],
            [],
        ]
    ) { request in
        switch request {
        case .removeProfile(let id, _):
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id))]
            )
        default:
            return runtimeHandle(id: request.id, request: request, events: [])
        }
    }
    let owner = makeOwner(runtime: runtime)
    await owner.initialize()

    let result = try await owner.removeProfile(profileName: "default-femme")

    #expect(result.ok)
    #expect(result.profileName == "default-femme")
    #expect(await owner.cachedProfiles().isEmpty)
}

// MARK: - Test Helpers

private actor FakeRuntime: SpeakSwiftlyRuntimeClient {
    private let submitHandler: @Sendable (WorkerRequest) -> RuntimeRequestHandle
    private var profileSnapshots: [[SpeakSwiftlyCore.ProfileSummary]]
    private var statusContinuations = [AsyncStream<WorkerStatusEvent>.Continuation]()

    init(
        profileSnapshots: [[SpeakSwiftlyCore.ProfileSummary]] = [],
        submitHandler: @escaping @Sendable (WorkerRequest) -> RuntimeRequestHandle
    ) {
        self.profileSnapshots = profileSnapshots
        self.submitHandler = submitHandler
    }

    func runtimeStatusEvents() async -> AsyncStream<WorkerStatusEvent> {
        AsyncStream { continuation in
            statusContinuations.append(continuation)
        }
    }

    func runtimeSubmit(_ request: WorkerRequest) async -> RuntimeRequestHandle {
        if case .listProfiles(let id) = request, profileSnapshots.isEmpty == false {
            let snapshot = profileSnapshots.removeFirst()
            return runtimeHandle(
                id: id,
                request: request,
                events: [.completed(.init(id: id, profiles: snapshot))]
            )
        }
        return submitHandler(request)
    }

    func runtimeStart() async {}

    func runtimeShutdown() async {}

    func emitStatus(_ status: WorkerStatusEvent) {
        statusContinuations.forEach { $0.yield(status) }
    }
}

private actor EventRecorder {
    private var events = [WorkerLineEnvelope]()

    func record(_ event: WorkerLineEnvelope) {
        events.append(event)
    }

    func snapshot() -> [WorkerLineEnvelope] {
        events
    }
}

private func makeOwner(runtime: any SpeakSwiftlyRuntimeClient) -> SpeakSwiftlyOwner {
    SpeakSwiftlyOwner(
        settings: .fromEnvironment([:]),
        logger: Logger(label: "SpeakSwiftlyMCPTests"),
        makeRuntime: { runtime }
    )
}

private func runtimeHandle(
    id: String,
    request: WorkerRequest,
    events: [WorkerRequestStreamEvent]
) -> RuntimeRequestHandle {
    RuntimeRequestHandle(
        id: id,
        request: request,
        events: AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    )
}

private func runtimeThrowingHandle(
    id: String,
    request: WorkerRequest,
    prefixEvents: [WorkerRequestStreamEvent] = [],
    error: WorkerError
) -> RuntimeRequestHandle {
    RuntimeRequestHandle(
        id: id,
        request: request,
        events: AsyncThrowingStream { continuation in
            prefixEvents.forEach { continuation.yield($0) }
            continuation.finish(throwing: error)
        }
    )
}

private func eventually(
    timeoutNanoseconds: UInt64 = 500_000_000,
    intervalNanoseconds: UInt64 = 20_000_000,
    condition: @escaping @Sendable () async -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    Issue.record("Timed out waiting for async test condition to become true.")
}
