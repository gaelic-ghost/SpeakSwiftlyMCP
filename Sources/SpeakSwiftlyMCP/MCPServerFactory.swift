import Foundation
import Logging
import MCP

// MARK: - Factory

enum MCPServerFactory {
    static func buildServer(
        settings: ServerSettings,
        owner: SpeakSwiftlyOwner,
        logger: Logger
    ) async -> Server {
        let server = Server(
            name: "speak-to-user-mcp",
            version: "0.1.1",
            title: "SpeakSwiftlyMCP",
            instructions: """
            Local speech MCP server that owns an in-process SpeakSwiftly runtime, streams worker progress back to clients, and exposes both blocking and background speech playback tools plus operator-readable status resources.
            """,
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPTools.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]

            switch params.name {
            case "speak_live":
                let progressReporter = makeProgressReporter(
                    server: server,
                    meta: params._meta,
                    logger: logger
                )
                let result = try await owner.speakLive(
                    text: requiredString("text", in: arguments),
                    profileName: requiredString("profile_name", in: arguments),
                    onEvent: progressReporter
                )
                return try toolResult(result)

            case "speak_live_background":
                let result = try await owner.speakLiveBackground(
                    text: requiredString("text", in: arguments),
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(result)

            case "create_profile":
                let progressReporter = makeProgressReporter(
                    server: server,
                    meta: params._meta,
                    logger: logger
                )
                let result = try await owner.createProfile(
                    profileName: requiredString("profile_name", in: arguments),
                    text: requiredString("text", in: arguments),
                    voiceDescription: requiredString("voice_description", in: arguments),
                    outputPath: optionalString("output_path", in: arguments),
                    onEvent: progressReporter
                )
                return try toolResult(result)

            case "list_profiles":
                return try toolResult(try await owner.listProfiles())

            case "remove_profile":
                let progressReporter = makeProgressReporter(
                    server: server,
                    meta: params._meta,
                    logger: logger
                )
                let result = try await owner.removeProfile(
                    profileName: requiredString("profile_name", in: arguments),
                    onEvent: progressReporter
                )
                return try toolResult(result)

            case "status":
                return try toolResult(await owner.status())

            default:
                throw MCPError.methodNotFound(
                    "Tool '\(params.name)' is not registered on this SpeakSwiftly MCP server."
                )
            }
        }

        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: MCPResourcesCatalog.resources)
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            .init(templates: MCPResourcesCatalog.templates)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            switch params.uri {
            case "speak://status":
                let status = await owner.status()
                let payload = StatusResource(
                    serverMode: status.serverMode,
                    workerMode: status.workerMode,
                    profileCacheState: status.profileCacheState,
                    buildMetadataBuiltAt: status.buildMetadataBuiltAt,
                    buildMetadataSourceTreeFingerprint: status.buildMetadataSourceTreeFingerprint,
                    currentSourceTreeFingerprint: status.currentSourceTreeFingerprint,
                    runtimeCacheState: status.runtimeCacheState,
                    runtimeCacheWarning: status.runtimeCacheWarning,
                    workerFailureSummary: status.workerFailureSummary,
                    profileCacheWarning: status.profileCacheWarning,
                    lastWorkerEvent: status.workerDiagnostics.lastEvent,
                    lastWarningEvent: status.workerDiagnostics.lastWarningEvent,
                    recentWorkerErrorCount: status.workerDiagnostics.recentErrorCount,
                    recentWorkerWarningCount: status.workerDiagnostics.recentWarningCount,
                    lastProfileRefreshAt: status.lastProfileRefreshAt
                )
                return try resourceResult(uri: params.uri, payload: payload)

            case "speak://profiles":
                let payload = await owner.cachedProfiles().map {
                    ProfileMetadataResource(
                        profileName: $0.profileName,
                        createdAt: $0.createdAt
                    )
                }
                return try resourceResult(uri: params.uri, payload: payload)

            case "speak://playback-jobs":
                return try resourceResult(uri: params.uri, payload: await owner.playbackJobs())

            case "speak://runtime":
                return try resourceResult(
                    uri: params.uri,
                    payload: RuntimeResource(
                        host: settings.host,
                        port: settings.port,
                        mcpPath: settings.mcpPath,
                        xcodeBuildConfiguration: settings.xcodeBuildConfiguration,
                        customProfileRootConfigured: settings.speakswiftlyProfileRoot != nil
                    )
                )

            default:
                if let profileName = profileDetailName(from: params.uri) {
                    guard let profile = await owner.cachedProfile(profileName) else {
                        throw MCPError.invalidRequest(
                            "No cached SpeakSwiftly profile matched that profile name. Refresh or recreate the profile before requesting detail."
                        )
                    }
                    return try resourceResult(uri: params.uri, payload: profile)
                }

                if let playbackJobID = playbackJobID(from: params.uri) {
                    guard let job = await owner.playbackJob(playbackJobID) else {
                        throw MCPError.invalidRequest(
                            "No tracked background playback job matched that job id. Request a new background playback or read speak://playback-jobs first."
                        )
                    }
                    return try resourceResult(uri: params.uri, payload: job)
                }

                throw MCPError.invalidRequest(
                    "Resource '\(params.uri)' is not available on this SpeakSwiftly MCP server."
                )
            }
        }

        await server.withMethodHandler(ListPrompts.self) { _ in
            .init(prompts: MCPPromptsCatalog.prompts)
        }

        await server.withMethodHandler(GetPrompt.self) { params in
            let arguments = params.arguments ?? [:]
            switch params.name {
            case "draft_profile_voice_description":
                let profileGoal = try requiredPromptString("profile_goal", in: arguments)
                let voiceTraits = try requiredPromptString("voice_traits", in: arguments)
                let constraints = textIfPresent("constraints", in: arguments)
                let deliveryStyle = textIfPresent("delivery_style", in: arguments)
                let body = """
                Write exactly one concise natural-language voice description for a reusable speech profile.
                Profile goal: \(profileGoal)
                Primary language: \(textIfPresent("language", in: arguments) ?? "Auto")
                Requested voice traits: \(voiceTraits)
                \(deliveryStyle.map { "Delivery style guidance: \($0)" } ?? "")
                \(constraints.map { "Additional constraints: \($0)" } ?? "")
                Focus on concrete timbre, affect, pacing, and speaking texture. Mention age or gender presentation only if explicitly requested above. Do not add bullets, labels, surrounding explanation, or more than one candidate.
                """
                return .init(
                    description: "Reusable authoring prompt for profile voice descriptions.",
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            case "draft_profile_source_text":
                let language = try requiredPromptString("language", in: arguments)
                let personaOrContext = try requiredPromptString("persona_or_context", in: arguments)
                let body = """
                Write spoken sample text for a voice-profile creation flow.
                Language: \(language)
                Persona or context: \(personaOrContext)
                Length hint: \(textIfPresent("length_hint", in: arguments) ?? "short paragraph")
                \(textIfPresent("style_notes", in: arguments).map { "Style notes: \($0)" } ?? "")
                The text should sound natural when read aloud, include enough phrasing variation to show rhythm and expression, and avoid meta commentary. Return only the sample text.
                """
                return .init(
                    description: "Reusable authoring prompt for profile source text.",
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            case "draft_voice_design_instruction":
                let spokenText = try requiredPromptString("spoken_text", in: arguments)
                let emotion = try requiredPromptString("emotion", in: arguments)
                let deliveryStyle = try requiredPromptString("delivery_style", in: arguments)
                let body = """
                Write exactly one natural-language instruction for a speech generation model that supports voice-design style prompting.
                Spoken text: \(spokenText)
                Language: \(textIfPresent("language", in: arguments) ?? "Auto")
                Target emotion: \(emotion)
                Delivery style: \(deliveryStyle)
                \(textIfPresent("constraints", in: arguments).map { "Additional constraints: \($0)" } ?? "")
                Describe how the line should sound without rewriting the spoken text. Focus on tone, pacing, emphasis, and prosody. Return only the instruction.
                """
                return .init(
                    description: "Reusable authoring prompt for future voice-design instructions.",
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            case "draft_background_playback_notice":
                let spokenTextSummary = try requiredPromptString("spoken_text_summary", in: arguments)
                let playbackJobID = try requiredPromptString("playback_job_id", in: arguments)
                let statusResourceURI = try requiredPromptString("status_resource_uri", in: arguments)
                let body = """
                Write exactly one short operator-facing acknowledgement for a speech playback job that was queued in the background.
                Spoken text summary: \(spokenTextSummary)
                Playback job id: \(playbackJobID)
                Status resource URI: \(statusResourceURI)
                Requested tone: \(textIfPresent("tone", in: arguments) ?? "calm and direct")
                State that playback was queued, avoid promising that playback has already finished, and point to the status resource for follow-up. Return only the acknowledgement text.
                """
                return .init(
                    description: "Reusable operator-facing prompt for background playback notices.",
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            default:
                throw MCPError.methodNotFound(
                    "Prompt '\(params.name)' is not registered on this SpeakSwiftly MCP server."
                )
            }
        }

        return server
    }

    // MARK: Helpers

    private static func makeProgressReporter(
        server: Server,
        meta: Metadata?,
        logger: Logger
    ) -> (@Sendable (WorkerLineEnvelope) async -> Void)? {
        guard let token = meta?.progressToken else { return nil }

        let progressLookup: [String: Double] = [
            "queued": 0.05,
            "started": 0.20,
            "loading_profile": 0.35,
            "starting_playback": 0.55,
            "buffering_audio": 0.75,
            "preroll_ready": 0.85,
            "playback_finished": 0.95,
            "loading_profile_model": 0.25,
            "generating_profile_audio": 0.55,
            "writing_profile_assets": 0.80,
            "exporting_profile_audio": 0.92,
                "removing_profile": 0.60,
        ]

        return { event in
            let stage = event.stage ?? event.event ?? "progress"
            let progress = progressLookup[stage] ?? 0.10
            do {
                try await server.notify(
                    Message<ProgressNotification>(
                        method: ProgressNotification.name,
                        params: .init(
                            progressToken: token,
                            progress: progress,
                            total: 1.0,
                            message: stage.replacingOccurrences(of: "_", with: " ")
                        )
                    )
                )
            } catch {
                logger.warning("Progress notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    private static func toolResult<Output: Codable>(_ output: Output) throws -> CallTool.Result {
        let data = try JSONEncoder().encode(output)
        let json = String(decoding: data, as: UTF8.self)
        return try .init(
            content: [.text(text: json, annotations: nil, _meta: nil)],
            structuredContent: output
        )
    }

    private static func resourceResult<Output: Codable>(
        uri: String,
        payload: Output
    ) throws -> ReadResource.Result {
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)
        return .init(
            contents: [.text(json, uri: uri, mimeType: "application/json")]
        )
    }

    private static func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
        guard let value = arguments[key]?.stringValue, value.isEmpty == false else {
            throw MCPError.invalidParams(
                "Tool arguments are missing the required string field '\(key)'."
            )
        }
        return value
    }

    private static func optionalString(_ key: String, in arguments: [String: Value]) -> String? {
        arguments[key]?.stringValue
    }

    private static func requiredPromptString(_ key: String, in arguments: [String: String]) throws -> String {
        guard let value = textIfPresent(key, in: arguments) else {
            throw MCPError.invalidParams(
                "Prompt arguments are missing the required string field '\(key)'."
            )
        }
        return value
    }

    private static func textIfPresent(_ key: String, in arguments: [String: String]) -> String? {
        guard let value = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        return value
    }

    private static func compactPrompt(_ raw: String) -> String {
        raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }

    private static func profileDetailName(from uri: String) -> String? {
        let prefix = "speak://profiles/"
        let suffix = "/detail"
        guard uri.hasPrefix(prefix), uri.hasSuffix(suffix) else { return nil }
        return String(uri.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private static func playbackJobID(from uri: String) -> String? {
        let prefix = "speak://playback-jobs/"
        guard uri.hasPrefix(prefix) else { return nil }
        return String(uri.dropFirst(prefix.count))
    }
}
