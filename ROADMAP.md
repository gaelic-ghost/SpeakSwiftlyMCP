# Project Roadmap

## Vision

- Deliver a Swift-native SpeakSwiftly MCP server that is stable enough for local accessibility workflows and straightforward for a future macOS app to install, supervise, and update as a LaunchAgent.

## Product principles

- Keep the MCP surface behavior aligned with `speak-to-user-mcp` while the Swift implementation matures.
- Prefer simple, directly traceable data flow over speculative architecture.
- Treat the current SpeakSwiftly worker bridge as compatibility infrastructure, not the final runtime boundary.
- Move toward a first-class `SpeakSwiftlyCore` API in bounded steps instead of one risky rewrite.

## Milestone Progress

- [x] Milestone 0: Foundation bootstrap
- [ ] Milestone 1: Runtime hardening and local ops
- [ ] Milestone 2: App-host integration readiness
- [ ] Milestone 3: `SpeakSwiftlyCore` v1 migration path

## Milestone 0: Foundation bootstrap

Scope:

- [x] Bootstrap the Swift executable package.
- [x] Mirror the current Python MCP tool, resource, and prompt surface.
- [x] Stand up streamable MCP HTTP serving with Hummingbird and the Swift MCP SDK.
- [x] Add baseline package tests and initial docs.

Tickets:

- [x] Add Swift MCP SDK, Hummingbird, ServiceLifecycle, and swift-log dependencies.
- [x] Implement the Hummingbird-to-MCP HTTP bridge.
- [x] Implement the current subprocess-backed SpeakSwiftly owner.
- [x] Add tests for settings normalization and mirrored surface names.
- [x] Add project README and roadmap.

Exit criteria:

- [x] `swift build` passes.
- [x] `swift test` passes.
- [x] The package exposes the expected MCP endpoint and surface definitions in code.

## Milestone 1: Runtime hardening and local ops

Scope:

- [ ] Make the current bridge-backed server more robust for day-to-day local use.
- [ ] Improve diagnostics so startup and worker failures are obvious and actionable.
- [ ] Add stronger verification around server startup and request flow.

Tickets:

- [ ] Add an integration-style test or scripted local smoke path for server startup.
- [ ] Validate and document the expected SpeakSwiftly runtime resolution paths more thoroughly.
- [ ] Tighten status output around worker readiness, failures, and cache freshness.
- [ ] Add operator-facing docs for common local failure modes and fixes.

Exit criteria:

- [ ] A local contributor can start the server and diagnose common setup failures without reading source first.
- [ ] The current bridge-backed runtime path feels stable enough to support app integration work.

## Milestone 2: App-host integration readiness

Scope:

- [ ] Prepare this executable to be managed cleanly by the forthcoming macOS app.
- [ ] Make configuration and process behavior predictable enough for LaunchAgent supervision.

Tickets:

- [ ] Finalize the environment contract the app will set for the server process.
- [ ] Document expected logging, health-check, and shutdown behavior for the app host.
- [ ] Add any missing hooks or ergonomics needed for app-driven install and update flows.

Exit criteria:

- [ ] The macOS app can treat this server as a stable executable dependency with a documented runtime contract.

## Milestone 3: `SpeakSwiftlyCore` v1 migration path

Scope:

- [ ] Replace the current JSONL bridge with a real first-class library API once `SpeakSwiftlyCore` exposes the right surfaces.
- [ ] Preserve the public MCP contract while swapping the backend implementation.

Tickets:

- [ ] Define the minimum in-process `SpeakSwiftlyCore` runtime API needed to replace the bridge.
- [ ] Add explicit event and result delivery APIs that do not depend on stdout or stderr.
- [ ] Refactor `SpeakSwiftlyMCP` to use the in-process runtime path behind the existing MCP surface.
- [ ] Remove obsolete subprocess-management code once the in-process path is verified.

Exit criteria:

- [ ] The Swift MCP server no longer depends on a subprocess-owned SpeakSwiftly bridge.
- [ ] The MCP surface remains compatible with the current tool, resource, and prompt contract.
