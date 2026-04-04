# SpeakSwiftlyMCP

Deprecated Swift executable package that previously served `SpeakSwiftly` through a standalone streamable MCP HTTP endpoint on macOS.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Development](#development)
- [Verification](#verification)
- [MCP Surface](#mcp-surface)
- [Configuration](#configuration)
- [License](#license)

## Overview

### Deprecation Notice

`SpeakSwiftlyMCP` is retired in favor of the combined [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md) package.

`SpeakSwiftlyServer` is now the canonical Swift host for both the app-facing HTTP API and the embedded MCP surface. It owns the shared `SpeakSwiftlyCore` runtime, the shared host state model, the shared config model, the shared live-update pipeline, and the current MCP tool, resource, and prompt surface.

No new feature work should land in `SpeakSwiftlyMCP`. Any runtime, MCP, config, transport, or app-integration work should now happen in [`../SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md).

`SpeakSwiftlyMCP` is the Swift-native sibling to [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp). It mirrors the current `SpeakSwiftly` queue-based speech and playback-control surface while replacing the Python host plus worker subprocess with an in-process `SpeakSwiftlyCore` runtime.

The current server uses [`swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) for MCP handling and [`Hummingbird`](https://github.com/hummingbird-project/hummingbird) for HTTP serving. By default it binds to `127.0.0.1:7341`, serves MCP at `/mcp`, and exposes a simple health endpoint at `/healthz`.

## Setup

For new setup, use [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md) instead of this package.

This package currently expects a sibling `SpeakSwiftly` checkout at `../SpeakSwiftly` because the package graph still uses a local path dependency.

Build the package with:

```bash
swift build
```

If you are iterating on the runtime too, build the adjacent package separately:

```bash
cd ../SpeakSwiftly
swift build
```

## Usage

For new local usage, run [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md) instead.

Run the local server with:

```bash
swift run SpeakSwiftlyMCP
```

Once it is running, the main MCP endpoint is:

```text
http://127.0.0.1:7341/mcp
```

That endpoint remains documented here only for historical compatibility. The actively maintained MCP surface now lives behind `SpeakSwiftlyServer` and its `APP_MCP_*` configuration.

## Development

This repository is now in retirement mode.

Allowed work here should be limited to deprecation messaging, release notes, archival cleanup, or narrowly scoped compatibility tasks that Gale explicitly chooses to keep alive for a concrete downstream consumer. The source of truth for all active Swift server work is [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md).

The package now builds as an explicit deprecation stub. The older standalone MCP implementation files remain in the repository for historical reference, but they are no longer part of the active SwiftPM target.

The Swift host is intentionally small and direct:

- [Main.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/Main.swift) bootstraps logging, the MCP transport, and the Hummingbird application.
- [MCPServerFactory.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/MCPServerFactory.swift) registers server metadata plus the mirrored tool, prompt, and resource handlers.
- [SpeakSwiftlyOwner.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/SpeakSwiftlyOwner.swift) owns the in-process runtime, cached profiles, playback-job tracking, and operator-facing status state.
- [HTTPBridge.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/HTTPBridge.swift) adapts Hummingbird requests and responses to the MCP HTTP transport.

Parity notes against `speak-to-user-mcp`:

- The public MCP surface is intentionally mirrored to the current `SpeakSwiftly` runtime: queue-based speech, split generation and playback queue inspection, explicit playback controls, and the same operator-readable JSON payload shapes.
- `queue_speech_live` returns after queue acceptance and keeps the local playback-job tracking resource so operators can follow the request through completion.
- The queue-management controls exposed by the current `SpeakSwiftlyCore` runtime are surfaced here too: `list_queue_generation`, `list_queue_playback`, `playback_pause`, `playback_resume`, `playback_state`, `clear_queue`, and `cancel_request`.
- `list_profiles` now returns the cached in-memory snapshot instead of forcing a fresh runtime request on every call, which matches the Python host behavior and the tool description.
- Late background-playback failures now store the plain worker error message instead of a type-qualified Swift `localizedDescription`.

Unlike the Python host, this Swift package does not currently manage a cached Xcode runtime directory, LaunchAgent scripts, or `.env` files. The runtime is started in-process through `SpeakSwiftlyCore`.

## Verification

If you are validating current Swift server behavior, prefer verifying [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md) first.

Run the local package checks before committing:

```bash
swift build
swift test
```

The real `SpeakSwiftly` end-to-end suite is intentionally optional and intentionally serialized. It only runs when you opt in, it acquires an exclusive lock at `/tmp/speak-to-user-mcp-model-loading-e2e.lock`, and it launches the server executable directly instead of nesting a second `swift run` inside `swift test`. For MLX-backed coverage it uses an Xcode-built `SpeakSwiftlyMCP` product so the required `default.metallib` bundle is present.

Opt into the real-server suite with:

```bash
SPEAK_TO_USER_MCP_E2E=1 swift test
```

## MCP Surface

This section is preserved as historical documentation for the retired standalone package. The canonical current MCP surface now lives in [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md).

Tool names:

- `queue_speech_live`
- `create_profile`
- `list_profiles`
- `remove_profile`
- `list_queue_generation`
- `list_queue_playback`
- `playback_pause`
- `playback_resume`
- `playback_state`
- `clear_queue`
- `cancel_request`
- `status`

Prompt names:

- `draft_profile_voice_description`
- `draft_profile_source_text`
- `draft_voice_design_instruction`
- `draft_queue_playback_notice`

Resource URIs:

- `speak://status`
- `speak://profiles`
- `speak://playback-jobs`
- `speak://runtime`

Resource templates:

- `speak://profiles/{profile_name}/detail`
- `speak://playback-jobs/{playback_job_id}`

Privacy defaults:

- `speak://profiles` returns metadata only: `profile_name` and `created_at`.
- Detailed stored profile content remains behind `speak://profiles/{profile_name}/detail`.

## Configuration

These environment variables apply only to the retired standalone package. New config work belongs in [`SpeakSwiftlyServer`](../SpeakSwiftlyServer/README.md).

Configuration is environment-driven with the `SPEAK_TO_USER_MCP_` prefix.

Currently consumed directly by the executable:

- `SPEAK_TO_USER_MCP_HOST`
- `SPEAK_TO_USER_MCP_PORT`
- `SPEAK_TO_USER_MCP_MCP_PATH`

Currently parsed and surfaced through runtime/status metadata, but not yet wired into `SpeakSwiftlyCore` startup:

- `SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH`
- `SPEAK_TO_USER_MCP_SPEAKSWIFTLY_PROFILE_ROOT`
- `SPEAK_TO_USER_MCP_XCODE_BUILD_CONFIGURATION`
- `SPEAK_TO_USER_MCP_LAUNCHAGENT_LABEL`
- `SPEAK_TO_USER_MCP_LOG_DIRECTORY`

`SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH` defaults to `../SpeakSwiftly` for adjacent-checkout diagnostics.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
