import Foundation

// MARK: - Shared Scalars

enum JSONScalar: Hashable, Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

// MARK: - Worker Models

struct ProfileSummary: Hashable, Codable, Sendable {
    let profileName: String
    let createdAt: String
    let voiceDescription: String
    let sourceText: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case createdAt = "created_at"
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }

    init(
        profileName: String,
        createdAt: String,
        voiceDescription: String,
        sourceText: String
    ) {
        self.profileName = profileName
        self.createdAt = createdAt
        self.voiceDescription = voiceDescription
        self.sourceText = sourceText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.profileName = try container.decode(String.self, forKey: .profileName)
        self.voiceDescription = try container.decode(String.self, forKey: .voiceDescription)
        self.sourceText = try container.decode(String.self, forKey: .sourceText)

        if let stringValue = try? container.decode(String.self, forKey: .createdAt) {
            self.createdAt = stringValue
        } else if let doubleValue = try? container.decode(Double.self, forKey: .createdAt) {
            self.createdAt = normalizeAppleReferenceTimestamp(doubleValue)
        } else if let intValue = try? container.decode(Int.self, forKey: .createdAt) {
            self.createdAt = normalizeAppleReferenceTimestamp(Double(intValue))
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "SpeakSwiftly profile metadata used an unreadable created_at value."
            )
        }
    }
}

struct WorkerLogEvent: Hashable, Codable, Sendable {
    let event: String
    let level: String
    let ts: String
    let requestID: String?
    let op: String?
    let profileName: String?
    let queueDepth: Int?
    let elapsedMS: Int?
    let details: [String: JSONScalar]?

    enum CodingKeys: String, CodingKey {
        case event
        case level
        case ts
        case requestID = "request_id"
        case op
        case profileName = "profile_name"
        case queueDepth = "queue_depth"
        case elapsedMS = "elapsed_ms"
        case details
    }
}

struct WorkerDiagnosticsSummary: Hashable, Codable, Sendable {
    let lastEvent: String?
    let lastErrorMessage: String?
    let lastWarningEvent: String?
    let recentErrorCount: Int
    let recentWarningCount: Int
}

struct StatusResult: Hashable, Codable, Sendable {
    let serverMode: String
    let workerMode: String
    let profileCacheState: String
    let runtimeProductsPath: String?
    let workerBinaryPath: String?
    let buildSourcePath: String?
    let buildMetadataBuiltAt: String?
    let buildMetadataSourceTreeFingerprint: String?
    let currentSourceTreeFingerprint: String?
    let runtimeCacheState: String
    let runtimeCacheWarning: String?
    let xcodeBuildConfiguration: String
    let workerFailureSummary: String?
    let profileCacheWarning: String?
    let workerDiagnostics: WorkerDiagnosticsSummary
    let recentWorkerLogs: [WorkerLogEvent]
    let cachedProfiles: [ProfileSummary]
    let lastProfileRefreshAt: String?
    let host: String
    let port: Int
    let mcpPath: String

    enum CodingKeys: String, CodingKey {
        case serverMode = "server_mode"
        case workerMode = "worker_mode"
        case profileCacheState = "profile_cache_state"
        case runtimeProductsPath = "runtime_products_path"
        case workerBinaryPath = "worker_binary_path"
        case buildSourcePath = "build_source_path"
        case buildMetadataBuiltAt = "build_metadata_built_at"
        case buildMetadataSourceTreeFingerprint = "build_metadata_source_tree_fingerprint"
        case currentSourceTreeFingerprint = "current_source_tree_fingerprint"
        case runtimeCacheState = "runtime_cache_state"
        case runtimeCacheWarning = "runtime_cache_warning"
        case xcodeBuildConfiguration = "xcode_build_configuration"
        case workerFailureSummary = "worker_failure_summary"
        case profileCacheWarning = "profile_cache_warning"
        case workerDiagnostics = "worker_diagnostics"
        case recentWorkerLogs = "recent_worker_logs"
        case cachedProfiles = "cached_profiles"
        case lastProfileRefreshAt = "last_profile_refresh_at"
        case host
        case port
        case mcpPath = "mcp_path"
    }
}

struct ToolAck: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
}

struct CreateProfileResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let profileName: String
    let profilePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
        case profilePath = "profile_path"
    }
}

struct RemoveProfileResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let profileName: String

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
    }
}

struct ListProfilesResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let profiles: [ProfileSummary]
}

struct ActiveRequestSummary: Hashable, Codable, Sendable {
    let id: String
    let op: String
    let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }
}

struct QueuedRequestSummary: Hashable, Codable, Sendable {
    let id: String
    let op: String
    let profileName: String?
    let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case queuePosition = "queue_position"
    }
}

struct ListQueueResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let queueType: String
    let activeRequest: ActiveRequestSummary?
    let queue: [QueuedRequestSummary]

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case queue
    }
}

struct PlaybackStateResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let playbackState: PlaybackStateResource

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case playbackState = "playback_state"
    }
}

struct PlaybackStateResource: Hashable, Codable, Sendable {
    let state: String
    let activeRequest: ActiveRequestSummary?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

struct ClearQueueResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case clearedCount = "cleared_count"
    }
}

struct CancelRequestResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case cancelledRequestID = "cancelled_request_id"
    }
}

struct QueueSpeechLiveResult: Hashable, Codable, Sendable {
    let id: String
    let ok: Bool
    let profileName: String
    let playbackJobID: String
    let playbackState: String
    let acceptedAt: String
    let launchedAt: String?
    let launchStage: String?
    let statusResourceURI: String

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
        case playbackJobID = "playback_job_id"
        case playbackState = "playback_state"
        case acceptedAt = "accepted_at"
        case launchedAt = "launched_at"
        case launchStage = "launch_stage"
        case statusResourceURI = "status_resource_uri"
    }
}

struct ProfileMetadataResource: Hashable, Codable, Sendable {
    let profileName: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case createdAt = "created_at"
    }
}

struct StatusResource: Hashable, Codable, Sendable {
    let serverMode: String
    let workerMode: String
    let profileCacheState: String
    let buildMetadataBuiltAt: String?
    let buildMetadataSourceTreeFingerprint: String?
    let currentSourceTreeFingerprint: String?
    let runtimeCacheState: String
    let runtimeCacheWarning: String?
    let workerFailureSummary: String?
    let profileCacheWarning: String?
    let lastWorkerEvent: String?
    let lastWarningEvent: String?
    let recentWorkerErrorCount: Int
    let recentWorkerWarningCount: Int
    let lastProfileRefreshAt: String?

    enum CodingKeys: String, CodingKey {
        case serverMode = "server_mode"
        case workerMode = "worker_mode"
        case profileCacheState = "profile_cache_state"
        case buildMetadataBuiltAt = "build_metadata_built_at"
        case buildMetadataSourceTreeFingerprint = "build_metadata_source_tree_fingerprint"
        case currentSourceTreeFingerprint = "current_source_tree_fingerprint"
        case runtimeCacheState = "runtime_cache_state"
        case runtimeCacheWarning = "runtime_cache_warning"
        case workerFailureSummary = "worker_failure_summary"
        case profileCacheWarning = "profile_cache_warning"
        case lastWorkerEvent = "last_worker_event"
        case lastWarningEvent = "last_warning_event"
        case recentWorkerErrorCount = "recent_worker_error_count"
        case recentWorkerWarningCount = "recent_worker_warning_count"
        case lastProfileRefreshAt = "last_profile_refresh_at"
    }
}

struct RuntimeResource: Hashable, Codable, Sendable {
    let host: String
    let port: Int
    let mcpPath: String
    let xcodeBuildConfiguration: String
    let customProfileRootConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case mcpPath = "mcp_path"
        case xcodeBuildConfiguration = "xcode_build_configuration"
        case customProfileRootConfigured = "custom_profile_root_configured"
    }
}

struct PlaybackJobResource: Hashable, Codable, Sendable {
    let playbackJobID: String
    let profileName: String
    let playbackState: String
    let acceptedAt: String
    let launchedAt: String?
    let completedAt: String?
    let launchStage: String?
    let lastStage: String?
    let textPreview: String
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case playbackJobID = "playback_job_id"
        case profileName = "profile_name"
        case playbackState = "playback_state"
        case acceptedAt = "accepted_at"
        case launchedAt = "launched_at"
        case completedAt = "completed_at"
        case launchStage = "launch_stage"
        case lastStage = "last_stage"
        case textPreview = "text_preview"
        case errorMessage = "error_message"
    }
}

// MARK: - Helpers

func iso8601Timestamp(_ date: Date?) -> String? {
    guard let date else { return nil }
    return ISO8601DateFormatter().string(from: date)
}

private func normalizeAppleReferenceTimestamp(_ seconds: Double) -> String {
    let reference = Date(timeIntervalSinceReferenceDate: seconds)
    return ISO8601DateFormatter().string(from: reference)
}
