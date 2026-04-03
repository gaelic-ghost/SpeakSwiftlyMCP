import Foundation
import Logging
import SpeakSwiftlyCore

// MARK: - Worker Transport Types

struct WorkerLineEnvelope: Sendable {
    let id: String?
    let event: String?
    let stage: String?
    let reason: String?
    let queuePosition: Int?
    let op: String?
    let ok: Bool?
    let code: String?
    let message: String?
}

private struct PlaybackJob: Hashable, Sendable {
    let playbackJobID: String
    let profileName: String
    let textPreview: String
    let acceptedAt: Date
    var playbackState: String
    var launchedAt: Date?
    var completedAt: Date?
    var launchStage: String?
    var lastStage: String?
    var errorMessage: String?
}

enum SpeakSwiftlyOwnerError: LocalizedError {
    case workerUnavailable(String)
    case requestRejected(code: String, message: String)
    case invalidWorkerOutput(String)

    var errorDescription: String? {
        switch self {
        case .workerUnavailable(let message):
            return message
        case .requestRejected(_, let message):
            return message
        case .invalidWorkerOutput(let message):
            return message
        }
    }
}

// MARK: - Owner

actor SpeakSwiftlyOwner {
    private let settings: ServerSettings
    private let logger: Logger

    private var runtime: WorkerRuntime?
    private var statusTask: Task<Void, Never>?
    private var profiles: [ProfileSummary] = []
    private var playbackJobsByID: [String: PlaybackJob] = [:]
    private var playbackJobOrder: [String] = []
    private var workerLogs: [WorkerLogEvent] = []
    private var workerMode = "stopped"
    private var workerFailureSummary: String?
    private var profileCacheState = "uninitialized"
    private var profileCacheWarning: String?
    private var lastProfileRefreshAt: Date?
    private var lastWorkerStatusStage: String?

    init(settings: ServerSettings, logger: Logger) {
        self.settings = settings
        self.logger = logger
    }

    // MARK: Lifecycle

    func initialize() async {
        guard runtime == nil else { return }

        workerMode = "initializing"
        workerFailureSummary = nil
        profileCacheState = "warming"
        appendWorkerLog(
            WorkerLogEvent(
                event: "runtime_initialization_started",
                level: "info",
                ts: iso8601Timestamp(Date()) ?? "",
                requestID: nil,
                op: nil,
                profileName: nil,
                queueDepth: nil,
                elapsedMS: nil,
                details: nil
            )
        )

        let runtime = await SpeakSwiftly.makeLiveRuntime()
        self.runtime = runtime
        startStatusObservation(for: runtime)
        await runtime.start()

        do {
            try await refreshProfiles()
            if workerMode == "initializing" {
                workerMode = "ready"
            }
        } catch {
            workerMode = "failed"
            workerFailureSummary = error.localizedDescription
            profileCacheState = "uninitialized"
            profileCacheWarning = error.localizedDescription
            appendErrorLog(
                event: "runtime_initialization_failed",
                message: error.localizedDescription
            )
            logger.error("SpeakSwiftly runtime failed to initialize: \(error.localizedDescription)")
        }
    }

    func shutdown() async {
        statusTask?.cancel()
        statusTask = nil

        if let runtime {
            await runtime.shutdown()
        }

        runtime = nil
        workerMode = "stopped"
        profileCacheState = "uninitialized"
        appendWorkerLog(
            WorkerLogEvent(
                event: "runtime_shutdown_completed",
                level: "info",
                ts: iso8601Timestamp(Date()) ?? "",
                requestID: nil,
                op: nil,
                profileName: nil,
                queueDepth: nil,
                elapsedMS: nil,
                details: nil
            )
        )
    }

    // MARK: MCP Operations

    func speakLive(
        text: String,
        profileName: String,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> SpeakLiveResult {
        let request = WorkerRequest.speakLive(
            id: UUID().uuidString,
            text: text,
            profileName: profileName
        )
        let handle = try await submit(request)
        let success = try await awaitCompletion(for: handle, onEvent: onEvent)
        return SpeakLiveResult(id: success.id, ok: success.ok)
    }

    func speakLiveBackground(text: String, profileName: String) async throws -> SpeakLiveBackgroundResult {
        let playbackJobID = "playback-\(UUID().uuidString)"
        let request = WorkerRequest.speakLiveBackground(
            id: playbackJobID,
            text: text,
            profileName: profileName
        )
        let handle = try await submit(request)

        let acceptedAt = Date()
        playbackJobsByID[playbackJobID] = PlaybackJob(
            playbackJobID: playbackJobID,
            profileName: profileName,
            textPreview: textPreview(text),
            acceptedAt: acceptedAt,
            playbackState: "queued",
            launchedAt: nil,
            completedAt: nil,
            launchStage: nil,
            lastStage: nil,
            errorMessage: nil
        )
        playbackJobOrder.append(playbackJobID)
        trimPlaybackJobs()

        let launched = AsyncSignal()
        let completionWatcher = Task {
            do {
                for try await event in handle.events {
                    self.recordPlaybackEvent(event, playbackJobID: playbackJobID)

                    switch event {
                    case .acknowledged, .started, .completed:
                        await launched.fire()
                    case .progress(let progress):
                        if [
                            WorkerProgressStage.startingPlayback,
                            .prerollReady,
                            .playbackFinished,
                        ].contains(progress.stage) {
                            await launched.fire()
                        }
                    case .queued:
                        break
                    }
                }

                self.completePlaybackJob(playbackJobID, errorMessage: nil)
            } catch {
                self.completePlaybackJob(playbackJobID, errorMessage: error.localizedDescription)
                await launched.fire()
            }
        }

        await launched.wait()
        _ = completionWatcher

        let playbackJob = playbackJobsByID[playbackJobID]
        return SpeakLiveBackgroundResult(
            id: playbackJobID,
            ok: true,
            profileName: profileName,
            playbackJobID: playbackJobID,
            playbackState: playbackJob?.playbackState ?? "queued",
            acceptedAt: iso8601Timestamp(acceptedAt)!,
            launchedAt: iso8601Timestamp(playbackJob?.launchedAt),
            launchStage: playbackJob?.launchStage,
            statusResourceURI: "speak://playback-jobs/\(playbackJobID)"
        )
    }

    func createProfile(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> CreateProfileResult {
        let request = WorkerRequest.createProfile(
            id: UUID().uuidString,
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath
        )
        let handle = try await submit(request)
        let success = try await awaitCompletion(for: handle, onEvent: onEvent)
        try await refreshProfiles()

        guard let completedProfileName = success.profileName,
              let profilePath = success.profilePath
        else {
            throw SpeakSwiftlyOwnerError.invalidWorkerOutput(
                "SpeakSwiftly completed create_profile without returning the profile name and profile path."
            )
        }

        return CreateProfileResult(
            id: success.id,
            ok: success.ok,
            profileName: completedProfileName,
            profilePath: profilePath
        )
    }

    func listProfiles() async throws -> ListProfilesResult {
        try await refreshProfiles()
        return ListProfilesResult(id: "cached-profiles", ok: true, profiles: profiles)
    }

    func removeProfile(
        profileName: String,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> RemoveProfileResult {
        let request = WorkerRequest.removeProfile(
            id: UUID().uuidString,
            profileName: profileName
        )
        let handle = try await submit(request)
        let success = try await awaitCompletion(for: handle, onEvent: onEvent)
        try await refreshProfiles()

        return RemoveProfileResult(
            id: success.id,
            ok: success.ok,
            profileName: success.profileName ?? profileName
        )
    }

    func status() -> StatusResult {
        let diagnostics = WorkerDiagnosticsSummary(
            lastEvent: workerLogs.last?.event,
            lastErrorMessage: workerLogs.last(where: { $0.level == "error" })?.details?["message"]?.stringValue,
            lastWarningEvent: workerLogs.last(where: { $0.level == "warning" })?.event,
            recentErrorCount: workerLogs.filter { $0.level == "error" }.count,
            recentWarningCount: workerLogs.filter { $0.level == "warning" }.count
        )

        return StatusResult(
            serverMode: workerMode == "ready" && profileCacheState == "fresh" ? "ready" : "degraded",
            workerMode: workerMode,
            profileCacheState: profileCacheState,
            runtimeProductsPath: nil,
            workerBinaryPath: nil,
            buildSourcePath: settings.speakswiftlySourcePath?.path,
            buildMetadataBuiltAt: nil,
            buildMetadataSourceTreeFingerprint: nil,
            currentSourceTreeFingerprint: nil,
            runtimeCacheState: "in_process_library",
            runtimeCacheWarning: nil,
            xcodeBuildConfiguration: settings.xcodeBuildConfiguration,
            workerFailureSummary: workerFailureSummary,
            profileCacheWarning: profileCacheWarning,
            workerDiagnostics: diagnostics,
            recentWorkerLogs: workerLogs.suffix(50).map { $0 },
            cachedProfiles: profiles,
            lastProfileRefreshAt: iso8601Timestamp(lastProfileRefreshAt),
            host: settings.host,
            port: settings.port,
            mcpPath: settings.mcpPath
        )
    }

    func cachedProfiles() -> [ProfileSummary] {
        profiles
    }

    func cachedProfile(_ profileName: String) -> ProfileSummary? {
        profiles.first { $0.profileName == profileName }
    }

    func playbackJobs() -> [PlaybackJobResource] {
        playbackJobOrder.compactMap { playbackJobsByID[$0] }.map(Self.makePlaybackJobResource)
    }

    func playbackJob(_ playbackJobID: String) -> PlaybackJobResource? {
        playbackJobsByID[playbackJobID].map(Self.makePlaybackJobResource)
    }

    // MARK: Runtime Integration

    private func startStatusObservation(for runtime: WorkerRuntime) {
        statusTask?.cancel()
        statusTask = Task {
            let stream = await runtime.statusEvents()
            for await status in stream {
                self.handleStatusEvent(status)
            }
        }
    }

    private func handleStatusEvent(_ status: WorkerStatusEvent) {
        lastWorkerStatusStage = status.stage.rawValue

        switch status.stage {
        case .warmingResidentModel:
            workerMode = "warming"
            profileCacheState = profileCacheState == "fresh" ? "fresh" : "warming"
        case .residentModelReady:
            workerMode = "ready"
            workerFailureSummary = nil
        case .residentModelFailed:
            workerMode = "failed"
            workerFailureSummary = "SpeakSwiftly reported that its resident model failed to load."
        }

        appendWorkerLog(
            WorkerLogEvent(
                event: status.event,
                level: status.stage == .residentModelFailed ? "error" : "info",
                ts: iso8601Timestamp(Date()) ?? "",
                requestID: nil,
                op: nil,
                profileName: nil,
                queueDepth: nil,
                elapsedMS: nil,
                details: ["stage": .string(status.stage.rawValue)]
            )
        )
    }

    private func refreshProfiles() async throws {
        let request = WorkerRequest.listProfiles(id: UUID().uuidString)
        let handle = try await submit(request)
        let success = try await awaitCompletion(for: handle, onEvent: nil)

        guard let importedProfiles = success.profiles else {
            throw SpeakSwiftlyOwnerError.invalidWorkerOutput(
                "SpeakSwiftly completed list_profiles without returning the profile list."
            )
        }

        profiles = importedProfiles.map(Self.makeProfileSummary)
        lastProfileRefreshAt = Date()
        profileCacheState = "fresh"
        profileCacheWarning = nil
    }

    private func submit(_ request: WorkerRequest) async throws -> WorkerRequestHandle {
        guard let runtime else {
            throw SpeakSwiftlyOwnerError.workerUnavailable(
                "SpeakSwiftly is not ready yet. Wait for initialization to finish or inspect the status tool for details."
            )
        }

        return await runtime.submit(request)
    }

    private func awaitCompletion(
        for handle: WorkerRequestHandle,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)?
    ) async throws -> WorkerSuccessResponse {
        do {
            for try await event in handle.events {
                if let onEvent {
                    await onEvent(Self.makeWorkerLineEnvelope(from: event))
                }

                if case .completed(let success) = event {
                    return success
                }
            }
        } catch let error as WorkerError {
            appendErrorLog(event: "request_failed", message: error.message, requestID: handle.id)
            throw SpeakSwiftlyOwnerError.requestRejected(
                code: error.code.rawValue,
                message: error.message
            )
        } catch {
            appendErrorLog(event: "request_failed", message: error.localizedDescription, requestID: handle.id)
            throw SpeakSwiftlyOwnerError.workerUnavailable(
                "SpeakSwiftly stopped streaming request events before that request could complete. \(error.localizedDescription)"
            )
        }

        throw SpeakSwiftlyOwnerError.invalidWorkerOutput(
            "SpeakSwiftly ended the request event stream without a final completion event."
        )
    }

    // MARK: Playback Tracking

    private func recordPlaybackEvent(_ event: WorkerRequestStreamEvent, playbackJobID: String) {
        guard var job = playbackJobsByID[playbackJobID] else { return }

        switch event {
        case .queued(let queued):
            job.lastStage = queued.event.rawValue
            job.playbackState = "queued"
        case .acknowledged:
            job.lastStage = "acknowledged"
            job.playbackState = "queued"
        case .started(let started):
            job.lastStage = started.event.rawValue
        case .progress(let progress):
            job.lastStage = progress.stage.rawValue
            if [
                WorkerProgressStage.startingPlayback,
                .prerollReady,
                .playbackFinished,
            ].contains(progress.stage) {
                if job.launchedAt == nil {
                    job.launchedAt = Date()
                    job.launchStage = progress.stage.rawValue
                }
                if job.playbackState == "queued" {
                    job.playbackState = "running"
                }
            }
            if progress.stage == .playbackFinished {
                job.playbackState = "completed"
                job.completedAt = Date()
            }
        case .completed:
            job.lastStage = "completed"
            job.playbackState = "completed"
            job.completedAt = Date()
        }

        playbackJobsByID[playbackJobID] = job
    }

    private func completePlaybackJob(_ playbackJobID: String, errorMessage: String?) {
        guard var job = playbackJobsByID[playbackJobID] else { return }
        if let errorMessage {
            job.playbackState = "failed"
            job.errorMessage = errorMessage
            job.completedAt = Date()
        } else if job.playbackState != "completed" {
            job.playbackState = "running"
        }
        playbackJobsByID[playbackJobID] = job
    }

    private func trimPlaybackJobs() {
        if playbackJobOrder.count <= 20 { return }
        let overflow = playbackJobOrder.count - 20
        for staleID in playbackJobOrder.prefix(overflow) {
            playbackJobsByID.removeValue(forKey: staleID)
        }
        playbackJobOrder.removeFirst(overflow)
    }

    private static func makePlaybackJobResource(_ job: PlaybackJob) -> PlaybackJobResource {
        PlaybackJobResource(
            playbackJobID: job.playbackJobID,
            profileName: job.profileName,
            playbackState: job.playbackState,
            acceptedAt: iso8601Timestamp(job.acceptedAt)!,
            launchedAt: iso8601Timestamp(job.launchedAt),
            completedAt: iso8601Timestamp(job.completedAt),
            launchStage: job.launchStage,
            lastStage: job.lastStage,
            textPreview: job.textPreview,
            errorMessage: job.errorMessage
        )
    }

    private static func makeProfileSummary(_ profile: SpeakSwiftlyCore.ProfileSummary) -> ProfileSummary {
        ProfileSummary(
            profileName: profile.profileName,
            createdAt: iso8601Timestamp(profile.createdAt) ?? "",
            voiceDescription: profile.voiceDescription,
            sourceText: profile.sourceText
        )
    }

    private func textPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 96 {
            return trimmed
        }
        return String(trimmed.prefix(93)) + "..."
    }

    // MARK: Logging

    private static func makeWorkerLineEnvelope(from event: WorkerRequestStreamEvent) -> WorkerLineEnvelope {
        switch event {
        case .queued(let queued):
            return WorkerLineEnvelope(
                id: queued.id,
                event: queued.event.rawValue,
                stage: nil,
                reason: queued.reason.rawValue,
                queuePosition: queued.queuePosition,
                op: nil,
                ok: nil,
                code: nil,
                message: nil
            )
        case .acknowledged(let success):
            return WorkerLineEnvelope(
                id: success.id,
                event: nil,
                stage: nil,
                reason: nil,
                queuePosition: nil,
                op: nil,
                ok: success.ok,
                code: nil,
                message: nil
            )
        case .started(let started):
            return WorkerLineEnvelope(
                id: started.id,
                event: started.event.rawValue,
                stage: nil,
                reason: nil,
                queuePosition: nil,
                op: started.op,
                ok: nil,
                code: nil,
                message: nil
            )
        case .progress(let progress):
            return WorkerLineEnvelope(
                id: progress.id,
                event: progress.event.rawValue,
                stage: progress.stage.rawValue,
                reason: nil,
                queuePosition: nil,
                op: nil,
                ok: nil,
                code: nil,
                message: nil
            )
        case .completed(let success):
            return WorkerLineEnvelope(
                id: success.id,
                event: nil,
                stage: nil,
                reason: nil,
                queuePosition: nil,
                op: nil,
                ok: success.ok,
                code: nil,
                message: nil
            )
        }
    }

    private func appendErrorLog(
        event: String,
        message: String,
        requestID: String? = nil
    ) {
        appendWorkerLog(
            WorkerLogEvent(
                event: event,
                level: "error",
                ts: iso8601Timestamp(Date()) ?? "",
                requestID: requestID,
                op: nil,
                profileName: nil,
                queueDepth: nil,
                elapsedMS: nil,
                details: ["message": .string(message)]
            )
        )
    }

    private func appendWorkerLog(_ event: WorkerLogEvent) {
        workerLogs.append(event)
        if workerLogs.count > 50 {
            workerLogs.removeFirst(workerLogs.count - 50)
        }
    }
}

// MARK: - Async Signal

private actor AsyncSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func fire() {
        guard fired == false else { return }
        fired = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}
