# SpeakSwiftlyMCP

Swift executable package for serving SpeakSwiftly through a streamable Model Context Protocol server on macOS.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Development](#development)
- [Verification](#verification)
- [License](#license)
- [Command Reference](#command-reference)
- [Configuration](#configuration)

## Overview

SpeakSwiftlyMCP provides a Swift-native MCP host that mirrors the current `speak-to-user-mcp` tool, resource, and prompt surface while using [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP handling and [Hummingbird](https://github.com/hummingbird-project/hummingbird) for HTTP serving.

### Motivation

This package exists so SpeakSwiftly can be exposed through the same accessibility-focused MCP interface without depending on the Python server at runtime. It is also the server executable that a future macOS app can register and supervise as a LaunchAgent.

The server now links directly against `SpeakSwiftlyCore` and runs the `WorkerRuntime` in-process, which keeps the MCP surface aligned with `speak-to-user-mcp` without depending on a separate worker executable.

## Setup

1. Make sure the adjacent `SpeakSwiftly` checkout exists at `../SpeakSwiftly` so SwiftPM can resolve the local package dependency.
2. Build the server package:

```bash
swift build
```

3. If you want to validate the underlying library directly while iterating, build `SpeakSwiftly` too:

```bash
cd ../SpeakSwiftly
swift build
```

## Usage

Run the server locally with:

```bash
swift run SpeakSwiftlyMCP
```

By default the server binds to `127.0.0.1:7341`, exposes the MCP endpoint at `/mcp`, and exposes a simple health endpoint at `/healthz`.

The current MCP surface mirrors the Python server:

- Tools: `speak_live`, `speak_live_background`, `create_profile`, `list_profiles`, `remove_profile`, `status`
- Resources: `speak://status`, `speak://profiles`, `speak://playback-jobs`, `speak://runtime`
- Resource templates: `speak://profiles/{profile_name}/detail`, `speak://playback-jobs/{playback_job_id}`
- Prompts: `draft_profile_voice_description`, `draft_profile_source_text`, `draft_voice_design_instruction`, `draft_background_playback_notice`

## Development

The package is intentionally split into a small set of responsibilities:

- [Main.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/Main.swift) bootstraps logging, MCP transport, and the Hummingbird application.
- [MCPServerFactory.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/MCPServerFactory.swift) registers the mirrored MCP surface.
- [SpeakSwiftlyOwner.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/SpeakSwiftlyOwner.swift) owns the in-process `SpeakSwiftlyCore` runtime, playback-job tracking, and cached status state.
- [HTTPBridge.swift](/Users/galew/Workspace/SpeakSwiftlyMCP/Sources/SpeakSwiftlyMCP/HTTPBridge.swift) adapts Hummingbird request and response types to the MCP HTTP server transport.

## Verification

Run the local package checks before changing behavior:

```bash
swift build
swift test
```

## License

No license file is committed yet. Until a license is added to this repository, treat the code as not licensed for reuse.

## Command Reference

- Build the package:

```bash
swift build
```

- Run the test suite:

```bash
swift test
```

- Start the local MCP server:

```bash
swift run SpeakSwiftlyMCP
```

## Configuration

Configuration is environment-driven and uses the `SPEAK_TO_USER_MCP_` prefix.

Common settings:

- `SPEAK_TO_USER_MCP_HOST`
- `SPEAK_TO_USER_MCP_PORT`
- `SPEAK_TO_USER_MCP_MCP_PATH`
- `SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH`
- `SPEAK_TO_USER_MCP_SPEAKSWIFTLY_PROFILE_ROOT`
- `SPEAK_TO_USER_MCP_XCODE_BUILD_CONFIGURATION`
- `SPEAK_TO_USER_MCP_LAUNCHAGENT_LABEL`
- `SPEAK_TO_USER_MCP_LOG_DIRECTORY`

`SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH` is used for adjacent-checkout diagnostics and defaults to `../SpeakSwiftly`.
