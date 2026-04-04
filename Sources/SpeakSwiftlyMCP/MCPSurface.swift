import Foundation
import MCP

// MARK: - Surface

enum MCPTools {
    static let toolNames: Set<String> = [
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
    ]

    static let definitions: [Tool] = [
        Tool(
            name: "queue_speech_live",
            description: "Queue live speech playback with a stored SpeakSwiftly profile and return once SpeakSwiftly has accepted the playback job.",
            inputSchema: [
                "type": "object",
                "required": ["text", "profile_name"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "create_profile",
            description: "Create a new stored SpeakSwiftly voice profile.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "text", "voice_description"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "text": ["type": "string"],
                    "voice_description": ["type": "string"],
                    "output_path": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "list_profiles",
            description: "Return the in-memory snapshot of available SpeakSwiftly profiles.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "remove_profile",
            description: "Remove a stored SpeakSwiftly voice profile.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name"],
                "properties": [
                    "profile_name": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "list_queue_generation",
            description: "Return the active SpeakSwiftly generation request plus the currently queued generation work, if any.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "list_queue_playback",
            description: "Return the active SpeakSwiftly playback request plus the currently queued playback work, if any.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "playback_pause",
            description: "Pause the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "playback_resume",
            description: "Resume the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "playback_state",
            description: "Return the current SpeakSwiftly playback state snapshot, including the active playback request when one exists.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "clear_queue",
            description: "Cancel all currently queued SpeakSwiftly requests without interrupting the active request.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "cancel_request",
            description: "Cancel one queued or active SpeakSwiftly request by request id.",
            inputSchema: [
                "type": "object",
                "required": ["request_id"],
                "properties": [
                    "request_id": ["type": "string"],
                ],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "status",
            description: "Report worker readiness, cached profiles, and effective runtime config.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
    ]
}

enum MCPResourcesCatalog {
    static let resources: [Resource] = [
        Resource(
            name: "Speak Status",
            uri: "speak://status",
            description: "Safe operational summary of the SpeakSwiftly MCP host.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Cached Profiles",
            uri: "speak://profiles",
            description: "Metadata-only index of cached SpeakSwiftly profiles.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Playback Jobs",
            uri: "speak://playback-jobs",
            description: "Recent background speech playback jobs tracked by the local MCP host.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Runtime Summary",
            uri: "speak://runtime",
            description: "Safe runtime summary for the local SpeakSwiftly MCP host.",
            mimeType: "application/json"
        ),
    ]

    static let templates: [Resource.Template] = [
        Resource.Template(
            uriTemplate: "speak://profiles/{profile_name}/detail",
            name: "Profile Detail",
            description: "Detailed SpeakSwiftly profile information for one cached profile.",
            mimeType: "application/json"
        ),
        Resource.Template(
            uriTemplate: "speak://playback-jobs/{playback_job_id}",
            name: "Playback Job Detail",
            description: "Detailed state for one background speech playback job.",
            mimeType: "application/json"
        ),
    ]
}

enum MCPPromptsCatalog {
    static let promptNames: Set<String> = [
        "draft_profile_voice_description",
        "draft_profile_source_text",
        "draft_voice_design_instruction",
        "draft_queue_playback_notice",
    ]

    static let prompts: [Prompt] = [
        Prompt(
            name: "draft_profile_voice_description",
            title: "Draft Profile Voice Description",
            description: "Create a reusable natural-language voice description suitable for SpeakSwiftly profile creation and Qwen3-TTS-style instruction control.",
            arguments: [
                .init(name: "profile_goal", required: true),
                .init(name: "voice_traits", required: true),
                .init(name: "language"),
                .init(name: "delivery_style"),
                .init(name: "constraints"),
            ]
        ),
        Prompt(
            name: "draft_profile_source_text",
            title: "Draft Profile Source Text",
            description: "Create a spoken sample text that works well as source text for SpeakSwiftly profile creation.",
            arguments: [
                .init(name: "language", required: true),
                .init(name: "persona_or_context", required: true),
                .init(name: "length_hint"),
                .init(name: "style_notes"),
            ]
        ),
        Prompt(
            name: "draft_voice_design_instruction",
            title: "Draft Voice Design Instruction",
            description: "Create a natural-language voice-direction instruction aligned with Qwen3-TTS-style voice design inputs.",
            arguments: [
                .init(name: "spoken_text", required: true),
                .init(name: "emotion", required: true),
                .init(name: "delivery_style", required: true),
                .init(name: "language"),
                .init(name: "constraints"),
            ]
        ),
        Prompt(
            name: "draft_queue_playback_notice",
            title: "Draft Queued Playback Notice",
            description: "Create a short acknowledgement that spoken playback has been queued and tell the operator where to check job status.",
            arguments: [
                .init(name: "spoken_text_summary", required: true),
                .init(name: "playback_job_id", required: true),
                .init(name: "status_resource_uri", required: true),
                .init(name: "tone"),
            ]
        ),
    ]
}
