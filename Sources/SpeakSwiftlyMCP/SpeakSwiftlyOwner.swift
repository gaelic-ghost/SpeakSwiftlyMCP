import CryptoKit
import Foundation
import Logging

// MARK: - Runtime Resolution

struct ResolvedRuntime: Hashable, Sendable {
    let productsPath: URL
    let binaryPath: URL
    let buildSourcePath: URL?
}

// MARK: - Worker Transport Types

private struct WorkerRequestEnvelope: Encodable, Sendable {
    let id: String
    let op: String
    let text: String?
    let profileName: String?
    let voiceDescription: String?
    let outputPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case text
        case profileName = "profile_name"
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
    }
}

struct WorkerLineEnvelope: Decodable, Sendable {
    let id: String?
    let event: String?
    let stage: String?
    let reason: String?
    let queuePosition: Int?
    let op: String?
    let ok: Bool?
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case stage
        case reason
        case queuePosition = "queue_position"
        case op
        case ok
        case code
        case message
    }
}

private struct PendingRequest {
    let continuation: CheckedContinuation<Data, Error>
    let onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)?
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
    case runtimeMissing(String)
    case invalidWorkerOutput(String)

    var errorDescription: String? {
        switch self {
        case .workerUnavailable(let message):
            return message
        case .requestRejected(_, let message):
            return message
        case .runtimeMissing(let message):
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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pendingRequests: [String: PendingRequest] = [:]
    private var profiles: [ProfileSummary] = []
    private var playbackJobsByID: [String: PlaybackJob] = [:]
    private var playbackJobOrder: [String] = []
    private var workerLogs: [WorkerLogEvent] = []
    private var workerMode = "stopped"
    private var workerFailureSummary: String?
    private var profileCacheState = "uninitialized"
    private var profileCacheWarning: String?
    private var lastProfileRefreshAt: Date?
    private var resolvedRuntime: ResolvedRuntime?
    private var sourceTreeFingerprint: String?

    init(settings: ServerSettings, logger: Logger) {
        self.settings = settings
        self.logger = logger
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    // MARK: Lifecycle

    func initialize() async {
        guard process == nil else { return }
        workerMode = "initializing"
        workerFailureSummary = nil

        do {
            let runtime = try resolveRuntime()
            resolvedRuntime = runtime
            sourceTreeFingerprint = try runtime.buildSourcePath.map(sourceFingerprint)
            try startWorker(using: runtime)
            try await refreshProfiles()
            workerMode = "ready"
        } catch {
            workerMode = "failed"
            workerFailureSummary = error.localizedDescription
            profileCacheState = "uninitialized"
            logger.error("SpeakSwiftly worker failed to initialize: \(error.localizedDescription)")
        }
    }

    func shutdown() async {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        for (_, pending) in pendingRequests {
            pending.continuation.resume(throwing: SpeakSwiftlyOwnerError.workerUnavailable(
                "SpeakSwiftly shut down before that request completed."
            ))
        }
        pendingRequests.removeAll()

        if let process {
            if process.isRunning {
                process.terminate()
            }
            self.process = nil
        }

        stdinHandle = nil
        workerMode = "stopped"
        profileCacheState = "uninitialized"
    }

    // MARK: MCP Operations

    func speakLive(
        text: String,
        profileName: String,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> SpeakLiveResult {
        let data = try await sendRequest(
            WorkerRequestEnvelope(
                id: UUID().uuidString,
                op: "speak_live",
                text: text,
                profileName: profileName,
                voiceDescription: nil,
                outputPath: nil
            ),
            onEvent: onEvent
        )
        return try decoder.decode(SpeakLiveResult.self, from: data)
    }

    func speakLiveBackground(text: String, profileName: String) async throws -> SpeakLiveBackgroundResult {
        try ensureWorkerReady()

        let jobID = "playback-\(UUID().uuidString)"
        var playbackJob = PlaybackJob(
            playbackJobID: jobID,
            profileName: profileName,
            textPreview: textPreview(text),
            acceptedAt: Date(),
            playbackState: "queued",
            launchedAt: nil,
            completedAt: nil,
            launchStage: nil,
            lastStage: nil,
            errorMessage: nil
        )
        playbackJobsByID[jobID] = playbackJob
        playbackJobOrder.append(jobID)
        trimPlaybackJobs()

        let launched = AsyncSignal()
        Task {
            do {
                _ = try await speakLive(text: text, profileName: profileName) { [weak launched] event in
                    await self.recordPlaybackEvent(event, playbackJobID: jobID)
                    if let stage = event.stage, ["starting_playback", "preroll_ready", "playback_finished"].contains(stage) {
                        await launched?.fire()
                    }
                }
                self.completePlaybackJob(jobID, errorMessage: nil)
            } catch {
                self.completePlaybackJob(jobID, errorMessage: error.localizedDescription)
                await launched.fire()
            }
        }

        await launched.wait()
        playbackJob = playbackJobsByID[jobID] ?? playbackJob

        return SpeakLiveBackgroundResult(
            id: jobID,
            ok: true,
            profileName: profileName,
            playbackJobID: jobID,
            playbackState: playbackJob.playbackState,
            acceptedAt: iso8601Timestamp(playbackJob.acceptedAt)!,
            launchedAt: iso8601Timestamp(playbackJob.launchedAt),
            launchStage: playbackJob.launchStage,
            statusResourceURI: "speak://playback-jobs/\(jobID)"
        )
    }

    func createProfile(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> CreateProfileResult {
        let data = try await sendRequest(
            WorkerRequestEnvelope(
                id: UUID().uuidString,
                op: "create_profile",
                text: text,
                profileName: profileName,
                voiceDescription: voiceDescription,
                outputPath: outputPath
            ),
            onEvent: onEvent
        )
        let result = try decoder.decode(CreateProfileResult.self, from: data)
        try await refreshProfiles()
        return result
    }

    func listProfiles() throws -> ListProfilesResult {
        try ensureWorkerReady()
        return ListProfilesResult(id: "cached-profiles", ok: true, profiles: profiles)
    }

    func removeProfile(
        profileName: String,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)? = nil
    ) async throws -> RemoveProfileResult {
        let data = try await sendRequest(
            WorkerRequestEnvelope(
                id: UUID().uuidString,
                op: "remove_profile",
                text: nil,
                profileName: profileName,
                voiceDescription: nil,
                outputPath: nil
            ),
            onEvent: onEvent
        )
        let result = try decoder.decode(RemoveProfileResult.self, from: data)
        try await refreshProfiles()
        return result
    }

    func status() -> StatusResult {
        let runtimeCacheState: String
        let runtimeCacheWarning: String?
        if let resolvedRuntime, let buildSourcePath = resolvedRuntime.buildSourcePath {
            if FileManager.default.fileExists(atPath: buildSourcePath.path) {
                runtimeCacheState = "current"
                runtimeCacheWarning = nil
            } else {
                runtimeCacheState = "source_missing"
                runtimeCacheWarning = "SpeakSwiftly was configured to use an adjacent source checkout, but that checkout is no longer available at '\(buildSourcePath.path)'."
            }
        } else {
            runtimeCacheState = "not_applicable"
            runtimeCacheWarning = nil
        }

        let diagnostics = WorkerDiagnosticsSummary(
            lastEvent: workerLogs.last?.event,
            lastErrorMessage: workerLogs.last(where: { $0.level == "error" })?.details?["message"]?.stringValue,
            lastWarningEvent: workerLogs.last(where: { $0.level != "error" })?.event,
            recentErrorCount: workerLogs.filter { $0.level == "error" }.count,
            recentWarningCount: workerLogs.filter { $0.level != "error" }.count
        )

        return StatusResult(
            serverMode: workerMode == "ready" && profileCacheState == "fresh" ? "ready" : "degraded",
            workerMode: workerMode,
            profileCacheState: profileCacheState,
            runtimeProductsPath: resolvedRuntime?.productsPath.path,
            workerBinaryPath: resolvedRuntime?.binaryPath.path,
            buildSourcePath: resolvedRuntime?.buildSourcePath?.path,
            buildMetadataBuiltAt: nil,
            buildMetadataSourceTreeFingerprint: sourceTreeFingerprint,
            currentSourceTreeFingerprint: sourceTreeFingerprint,
            runtimeCacheState: runtimeCacheState,
            runtimeCacheWarning: runtimeCacheWarning,
            xcodeBuildConfiguration: settings.xcodeBuildConfiguration,
            workerFailureSummary: workerFailureSummary,
            profileCacheWarning: profileCacheWarning,
            workerDiagnostics: diagnostics,
            recentWorkerLogs: workerLogs.suffix(50),
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

    // MARK: Worker Management

    private func resolveRuntime() throws -> ResolvedRuntime {
        let fileManager = FileManager.default

        if let runtimePath = settings.speakswiftlyRuntimePath {
            let binaryPath = runtimePath.appendingPathComponent("SpeakSwiftly")
            guard fileManager.isExecutableFile(atPath: binaryPath.path) else {
                throw SpeakSwiftlyOwnerError.runtimeMissing(
                    "SpeakSwiftly runtime path '\(runtimePath.path)' does not contain an executable 'SpeakSwiftly' binary."
                )
            }
            return ResolvedRuntime(
                productsPath: runtimePath,
                binaryPath: binaryPath,
                buildSourcePath: nil
            )
        }

        if let sourcePath = settings.speakswiftlySourcePath {
            let xcodeBinary = settings.cachedBinaryPath
            if fileManager.isExecutableFile(atPath: xcodeBinary.path) {
                return ResolvedRuntime(
                    productsPath: settings.cachedRuntimeProductsPath,
                    binaryPath: xcodeBinary,
                    buildSourcePath: sourcePath
                )
            }

            if let packageBinary = settings.packageDebugBinaryPath,
               fileManager.isExecutableFile(atPath: packageBinary.path)
            {
                return ResolvedRuntime(
                    productsPath: packageBinary.deletingLastPathComponent(),
                    binaryPath: packageBinary,
                    buildSourcePath: sourcePath
                )
            }

            throw SpeakSwiftlyOwnerError.runtimeMissing(
                "No usable SpeakSwiftly worker binary was found. Configure SPEAK_TO_USER_MCP_SPEAKSWIFTLY_RUNTIME_PATH or build the adjacent SpeakSwiftly checkout first."
            )
        }

        throw SpeakSwiftlyOwnerError.runtimeMissing(
            "SpeakSwiftly is not configured. Set SPEAK_TO_USER_MCP_SPEAKSWIFTLY_RUNTIME_PATH or SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH before starting the server."
        )
    }

    private func startWorker(using runtime: ResolvedRuntime) throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = runtime.binaryPath
        process.currentDirectoryURL = runtime.buildSourcePath ?? runtime.productsPath
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        if let profileRoot = settings.speakswiftlyProfileRoot {
            environment["SPEAKSWIFTLY_PROFILE_ROOT"] = profileRoot.path
        }
        process.environment = environment
        process.terminationHandler = { [logger] terminatedProcess in
            logger.warning(
                "SpeakSwiftly worker terminated with status \(terminatedProcess.terminationStatus)."
            )
        }

        try process.run()

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        stdoutTask = Task {
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    await self.handleStdoutLine(String(line))
                }
            } catch {
                self.appendWorkerLog(
                    WorkerLogEvent(
                        event: "worker_stdout_read_failed",
                        level: "warning",
                        ts: iso8601Timestamp(Date()) ?? "",
                        requestID: nil,
                        op: nil,
                        profileName: nil,
                        queueDepth: nil,
                        elapsedMS: nil,
                        details: ["message": .string(error.localizedDescription)]
                    )
                )
            }
        }

        stderrTask = Task {
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    await self.handleStderrLine(String(line))
                }
            } catch {
                self.appendWorkerLog(
                    WorkerLogEvent(
                        event: "worker_stderr_read_failed",
                        level: "warning",
                        ts: iso8601Timestamp(Date()) ?? "",
                        requestID: nil,
                        op: nil,
                        profileName: nil,
                        queueDepth: nil,
                        elapsedMS: nil,
                        details: ["message": .string(error.localizedDescription)]
                    )
                )
            }
        }
    }

    private func refreshProfiles() async throws {
        let data = try await sendRequest(
            WorkerRequestEnvelope(
                id: UUID().uuidString,
                op: "list_profiles",
                text: nil,
                profileName: nil,
                voiceDescription: nil,
                outputPath: nil
            ),
            onEvent: nil
        )
        let result = try decoder.decode(ListProfilesResult.self, from: data)
        profiles = result.profiles
        lastProfileRefreshAt = Date()
        profileCacheState = "fresh"
        profileCacheWarning = nil
    }

    private func sendRequest(
        _ request: WorkerRequestEnvelope,
        onEvent: (@Sendable (WorkerLineEnvelope) async -> Void)?
    ) async throws -> Data {
        try ensureWorkerReady()
        guard let stdinHandle else {
            throw SpeakSwiftlyOwnerError.workerUnavailable(
                "SpeakSwiftly is not connected because its stdin pipe is unavailable."
            )
        }

        let line = try encoder.encode(request) + Data([0x0A])

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[request.id] = PendingRequest(
                continuation: continuation,
                onEvent: onEvent
            )
            do {
                try stdinHandle.write(contentsOf: line)
            } catch {
                pendingRequests.removeValue(forKey: request.id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func ensureWorkerReady() throws {
        guard workerMode == "ready", process?.isRunning == true else {
            throw SpeakSwiftlyOwnerError.workerUnavailable(
                workerFailureSummary
                    ?? "SpeakSwiftly is not ready yet. Wait for the worker to finish starting or inspect the status tool for details."
            )
        }
    }

    // MARK: Worker Output

    private func handleStdoutLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let message = try decoder.decode(WorkerLineEnvelope.self, from: data)

            if message.event == "worker_status" {
                switch message.stage {
                case "resident_model_ready":
                    workerMode = "ready"
                case "resident_model_failed":
                    workerMode = "failed"
                    workerFailureSummary = "SpeakSwiftly reported that its resident model failed to load."
                default:
                    break
                }
            }

            if let requestID = message.id, let pending = pendingRequests[requestID] {
                if message.ok != nil {
                    pendingRequests.removeValue(forKey: requestID)
                    if message.ok == true {
                        pending.continuation.resume(returning: data)
                    } else {
                        pending.continuation.resume(
                            throwing: SpeakSwiftlyOwnerError.requestRejected(
                                code: message.code ?? "internal_error",
                                message: message.message ?? "SpeakSwiftly rejected that request without explaining why."
                            )
                        )
                    }
                    return
                }

                if let onEvent = pending.onEvent {
                    await onEvent(message)
                }
            }
        } catch {
            appendWorkerLog(
                WorkerLogEvent(
                    event: "worker_stdout_parse_failed",
                    level: "warning",
                    ts: iso8601Timestamp(Date()) ?? "",
                    requestID: nil,
                    op: nil,
                    profileName: nil,
                    queueDepth: nil,
                    elapsedMS: nil,
                    details: ["message": .string(line)]
                )
            )
        }
    }

    private func handleStderrLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }
        if let event = try? decoder.decode(WorkerLogEvent.self, from: data) {
            appendWorkerLog(event)
        } else {
            appendWorkerLog(
                WorkerLogEvent(
                    event: "worker_stderr_text",
                    level: "warning",
                    ts: iso8601Timestamp(Date()) ?? "",
                    requestID: nil,
                    op: nil,
                    profileName: nil,
                    queueDepth: nil,
                    elapsedMS: nil,
                    details: ["message": .string(line)]
                )
            )
        }
    }

    private func appendWorkerLog(_ event: WorkerLogEvent) {
        workerLogs.append(event)
        if workerLogs.count > 50 {
            workerLogs.removeFirst(workerLogs.count - 50)
        }
    }

    // MARK: Playback Tracking

    private func recordPlaybackEvent(_ event: WorkerLineEnvelope, playbackJobID: String) {
        guard var job = playbackJobsByID[playbackJobID] else { return }
        job.lastStage = event.stage ?? event.event

        if let stage = event.stage, ["starting_playback", "preroll_ready", "playback_finished"].contains(stage) {
            if job.launchedAt == nil {
                job.launchedAt = Date()
                job.launchStage = stage
            }
            if job.playbackState == "queued" {
                job.playbackState = "running"
            }
        }

        if event.stage == "playback_finished" {
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
        } else {
            job.playbackState = job.playbackState == "completed" ? "completed" : "running"
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

    private func textPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 96 {
            return trimmed
        }
        return String(trimmed.prefix(93)) + "..."
    }

    // MARK: Fingerprints

    private func sourceFingerprint(_ sourcePath: URL) throws -> String {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: sourcePath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var hasher = SHA256()
        while let next = enumerator?.nextObject() as? URL {
            if next.path.contains("/.build/") || next.path.contains("/.git/") {
                continue
            }
            let resourceValues = try next.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            hasher.update(data: Data(next.path.utf8))
            hasher.update(data: try Data(contentsOf: next))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
