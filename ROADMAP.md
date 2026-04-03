# Project Roadmap

## Vision

- Deliver a Swift-native SpeakSwiftly MCP server that is stable enough for local accessibility workflows and straightforward for a future macOS app to install, supervise, and update as a LaunchAgent.

## Product principles

- Keep the MCP surface behavior aligned with `speak-to-user-mcp` while the Swift implementation matures.
- Prefer simple, directly traceable data flow over speculative architecture.
- Prefer the first-class `SpeakSwiftlyCore` runtime directly when it keeps the server simpler and the data flow straighter.
- Finish cleanup work in complete passes instead of preserving transitional runtime scaffolding.

## Milestone Progress

- [x] Milestone 0: Foundation bootstrap
- [ ] Milestone 1: Runtime hardening and local ops
- [ ] Milestone 2: App-host integration readiness
- [x] Milestone 3: `SpeakSwiftlyCore` v1 migration path
- [ ] Milestone 4: Distributed dependency adoption
- [ ] Milestone 5: Transport and end-to-end test coverage

## Milestone 0: Foundation bootstrap

Scope:

- [x] Bootstrap the Swift executable package.
- [x] Mirror the current Python MCP tool, resource, and prompt surface.
- [x] Stand up streamable MCP HTTP serving with Hummingbird and the Swift MCP SDK.
- [x] Add baseline package tests and initial docs.

Tickets:

- [x] Add Swift MCP SDK, Hummingbird, ServiceLifecycle, and swift-log dependencies.
- [x] Implement the Hummingbird-to-MCP HTTP bridge.
- [x] Implement the first working SpeakSwiftly owner.
- [x] Add tests for settings normalization and mirrored surface names.
- [x] Add project README and roadmap.

Exit criteria:

- [x] `swift build` passes.
- [x] `swift test` passes.
- [x] The package exposes the expected MCP endpoint and surface definitions in code.

## Milestone 1: Runtime hardening and local ops

Scope:

- [ ] Make the in-process `SpeakSwiftlyCore` server more robust for day-to-day local use.
- [ ] Improve diagnostics so startup and worker failures are obvious and actionable.
- [ ] Add stronger verification around server startup and request flow.

Tickets:

- [ ] Add an integration-style test or scripted local smoke path for server startup.
- [ ] Validate and document the expected SpeakSwiftly runtime resolution paths more thoroughly.
- [ ] Tighten status output around worker readiness, failures, and cache freshness.
- [ ] Add operator-facing docs for common local failure modes and fixes.

Exit criteria:

- [ ] A local contributor can start the server and diagnose common setup failures without reading source first.
- [ ] The in-process runtime path feels stable enough to support app integration work.

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

- [x] Replace the old JSONL worker bridge with the in-process `SpeakSwiftlyCore` runtime.
- [x] Preserve the public MCP contract while swapping the backend implementation.

Tickets:

- [x] Define the minimum in-process `SpeakSwiftlyCore` runtime API needed to replace the bridge.
- [x] Add explicit event and result delivery APIs that do not depend on stdout or stderr.
- [x] Refactor `SpeakSwiftlyMCP` to use the in-process runtime path behind the existing MCP surface.
- [x] Remove obsolete subprocess-management code once the in-process path is verified.

Exit criteria:

- [x] The Swift MCP server no longer depends on a subprocess-owned SpeakSwiftly bridge.
- [x] The MCP surface remains compatible with the current tool, resource, and prompt contract.

## Milestone 4: Distributed dependency adoption

Scope:

- [ ] Stop depending on a sibling `../SpeakSwiftly` checkout for package resolution.
- [ ] Make `SpeakSwiftlyMCP` consumable from GitHub or a Swift package registry without local path wiring.

Tickets:

- [ ] Choose the distribution path for `SpeakSwiftly`: GitHub-based package dependency, package registry publication, or another stable Swift distribution channel.
- [ ] Update `SpeakSwiftly` packaging and release flow so `SpeakSwiftlyCore` can be consumed as a versioned external dependency.
- [ ] Replace the local path dependency in `SpeakSwiftlyMCP` with a versioned dependency once the published package is available.
- [ ] Update setup, release, and integration docs to describe the distributed dependency flow instead of the sibling-checkout flow.
- [ ] Verify that a clean checkout can build `SpeakSwiftlyMCP` without a local adjacent `SpeakSwiftly` repository.

Exit criteria:

- [ ] `SpeakSwiftlyMCP` builds from a clean checkout with only versioned external dependencies.
- [ ] The future macOS app and the `speak-to-user` monorepo no longer need local path assumptions to adopt new `SpeakSwiftlyMCP` releases.

## Milestone 5: Transport and end-to-end test coverage

Scope:

- [ ] Close the remaining source-level coverage gaps in the MCP transport and executable entrypoints.
- [ ] Add end-to-end-style verification for every public tool, resource, and prompt path that matters to local operators and the future app host.
- [ ] Keep the Swift contract visibly aligned with `SpeakSwiftlyServer` and `speak-to-user-mcp` as coverage expands.

Tickets:

- [ ] Add direct tests for `MCPServerFactory` so tool handlers, prompt handlers, resource handlers, and template reads are exercised through the assembled server surface instead of only through owner helpers.
- [ ] Add direct tests for `HTTPBridge` so streamable MCP HTTP routing, health checks, and response behavior are exercised without depending on manual local runs.
- [ ] Add targeted coverage for `Main` startup wiring so configuration loading, lifecycle startup, and failure reporting are verified at least once in an executable-style harness.
- [ ] Add end-to-end tests that cover each public tool path: `speak_live`, `speak_live_background`, `create_profile`, `list_profiles`, `remove_profile`, and `status`.
- [ ] Add end-to-end tests that cover each public resource path: `speak://status`, `speak://profiles`, `speak://playback-jobs`, `speak://runtime`, `speak://profiles/{profile_name}/detail`, and `speak://playback-jobs/{playback_job_id}`.
- [ ] Add end-to-end tests that cover each public prompt path and verify their stable names plus the essential shape of their arguments and output.
- [ ] Add negative-path coverage for transport-level failures, malformed requests, missing resources, and runtime initialization failures that propagate through the MCP server surface.
- [ ] Document which coverage is owner-level, transport-level, and end-to-end so future releases can see the remaining risk clearly.

Exit criteria:

- [ ] `MCPServerFactory`, `HTTPBridge`, and `Main` no longer sit at 0% coverage.
- [ ] Every public tool, resource, and prompt path has at least one automated end-to-end coverage path.
- [ ] A contributor can change the MCP surface and get fast test failures if the public contract drifts from the expected Swift and Python-compatible behavior.
