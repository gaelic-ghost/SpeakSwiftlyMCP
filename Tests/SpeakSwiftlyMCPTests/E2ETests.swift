import Darwin
import Foundation
import MCP
import Testing
@testable import SpeakSwiftlyMCP

// MARK: - End-to-End Tests

@Test
func realServerRunsProfileLifecycleAndPlaybackJobs() async throws {
    guard E2ETestConfiguration.isEnabled() else { return }
    let configuration = try E2ETestConfiguration.make()

    try await withExclusiveModelLoadingLock {
        try await withRunningServer(configuration: configuration) { url, process in
            try await withClient(url: url) { client in
                let initialStatus = try await step("call status tool before lifecycle checks") {
                    try await callTool(
                        "status",
                        arguments: nil,
                        using: client,
                        as: StatusResult.self
                    )
                }
                if initialStatus.workerMode != "ready" {
                    throw E2ETestError(
                        "The real server reported worker mode '\(initialStatus.workerMode)' instead of 'ready'.\n\(await process.diagnostics())"
                    )
                }
                #expect(initialStatus.profileCacheState == "fresh")

                let tools = try await step("list tools") {
                    try await client.listTools().tools
                }
                #expect(Set(tools.map(\.name)).isSuperset(of: Set(MCPTools.toolNames)))

                let prompts = try await step("list prompts") {
                    try await client.listPrompts().prompts
                }
                #expect(Set(prompts.map(\.name)).isSuperset(of: Set(MCPPromptsCatalog.promptNames)))

                let resources = try await step("list resources") {
                    try await client.listResources().resources
                }
                #expect(Set(resources.map(\.uri)).isSuperset(of: Set(MCPResourcesCatalog.resources.map(\.uri))))

                let templates = try await step("list resource templates") {
                    try await client.listResourceTemplates().templates
                }
                #expect(Set(templates.map(\.uriTemplate)).isSuperset(of: Set(MCPResourcesCatalog.templates.map(\.uriTemplate))))

                let prompt = try await step("fetch prompt content") {
                    try await client.getPrompt(
                        name: "draft_voice_design_instruction",
                        arguments: [
                            "spoken_text": "Hello there from the Swift end-to-end prompt path.",
                            "emotion": "warm reassurance",
                            "delivery_style": "steady and gentle",
                        ]
                    )
                }
                let promptText = try #require(text(from: prompt.messages.first?.content))
                #expect(promptText.contains("Hello there from the Swift end-to-end prompt path."))

                let runtimeResource = try await step("read runtime resource") {
                    try await readResource(
                        "speak://runtime",
                        using: client,
                        as: RuntimeResource.self
                    )
                }
                #expect(runtimeResource.port == configuration.port)
                #expect(runtimeResource.mcpPath == configuration.mcpPath)
                #expect(runtimeResource.xcodeBuildConfiguration == "Debug")
                #expect(runtimeResource.customProfileRootConfigured == true)

                let statusResource = try await step("read status resource") {
                    try await readResource(
                        "speak://status",
                        using: client,
                        as: StatusResource.self
                    )
                }
                #expect(statusResource.workerMode == "ready")
                #expect(statusResource.profileCacheState == "fresh")

                let profileName = "e2e-profile-\(UUID().uuidString.lowercased().prefix(8))"

                let createResult = try await step("create profile through live MCP tool") {
                    try await callTool(
                        "create_profile",
                        arguments: [
                            "profile_name": .string(profileName),
                            "text": .string("Hello there from SpeakSwiftlyMCP's Swift end-to-end coverage."),
                            "voice_description": .string("A calm, warm, feminine narrator voice."),
                        ],
                        meta: nil,
                        using: client,
                        as: CreateProfileResult.self
                    )
                }
                #expect(createResult.ok)
                #expect(createResult.profileName == profileName)

                let listedProfiles = try await step("list profiles after creation") {
                    try await callTool(
                        "list_profiles",
                        arguments: nil,
                        using: client,
                        as: ListProfilesResult.self
                    )
                }
                #expect(listedProfiles.profiles.contains { $0.profileName == profileName })

                let profilesResource = try await step("read profile metadata resource") {
                    try await readResource(
                        "speak://profiles",
                        using: client,
                        as: [ProfileMetadataResource].self
                    )
                }
                #expect(profilesResource.contains { $0.profileName == profileName })

                let profileDetail = try await step("read full stored profile detail resource") {
                    try await readResource(
                        "speak://profiles/\(profileName)/detail",
                        using: client,
                        as: ProfileSummary.self
                    )
                }
                #expect(profileDetail.profileName == profileName)
                #expect(profileDetail.voiceDescription == "A calm, warm, feminine narrator voice.")

                let speakResult = try await step("run foreground playback tool") {
                    try await callTool(
                        "speak_live",
                        arguments: [
                            "profile_name": .string(profileName),
                            "text": .string("Hello from the real SpeakSwiftly-backed Swift MCP end-to-end path."),
                        ],
                        meta: nil,
                        using: client,
                        as: SpeakLiveResult.self
                    )
                }
                #expect(speakResult.ok)

                let backgroundResult = try await step("run background playback tool") {
                    try await callTool(
                        "speak_live_background",
                        arguments: [
                            "profile_name": .string(profileName),
                            "text": .string("Hello from the queued background playback path."),
                        ],
                        meta: nil,
                        using: client,
                        as: SpeakLiveBackgroundResult.self
                    )
                }
                #expect(backgroundResult.ok)
                #expect(backgroundResult.profileName == profileName)
                #expect(
                    backgroundResult.playbackState == "queued"
                        || backgroundResult.playbackState == "running"
                        || backgroundResult.playbackState == "completed"
                )

                let completedPlaybackJob: PlaybackJobResource = try await eventually(
                    timeout: .seconds(30),
                    pollInterval: .milliseconds(250)
                ) {
                    let job = try await readResource(
                        backgroundResult.statusResourceURI,
                        using: client,
                        as: PlaybackJobResource.self
                    )
                    guard job.playbackState == "completed" else {
                        return nil
                    }
                    return job
                }
                #expect(completedPlaybackJob.playbackJobID == backgroundResult.playbackJobID)
                #expect(completedPlaybackJob.lastStage == "completed")
                #expect(completedPlaybackJob.completedAt != nil)

                let playbackJobs = try await step("read playback job list resource") {
                    try await readResource(
                        "speak://playback-jobs",
                        using: client,
                        as: [PlaybackJobResource].self
                    )
                }
                #expect(playbackJobs.contains { $0.playbackJobID == backgroundResult.playbackJobID })

                let removeResult = try await step("remove created profile") {
                    try await callTool(
                        "remove_profile",
                        arguments: ["profile_name": .string(profileName)],
                        meta: nil,
                        using: client,
                        as: RemoveProfileResult.self
                    )
                }
                #expect(removeResult.ok)
                #expect(removeResult.profileName == profileName)

                let finalProfiles = try await step("list profiles after removal") {
                    try await callTool(
                        "list_profiles",
                        arguments: nil,
                        using: client,
                        as: ListProfilesResult.self
                    )
                }
                #expect(finalProfiles.profiles.contains { $0.profileName == profileName } == false)

                let finalStatus = try await step("call final status tool") {
                    try await callTool(
                        "status",
                        arguments: nil,
                        using: client,
                        as: StatusResult.self
                    )
                }
                #expect(finalStatus.serverMode == "ready")
                #expect(finalStatus.workerMode == "ready")
                #expect(finalStatus.profileCacheState == "fresh")
                #expect(finalStatus.xcodeBuildConfiguration == "Debug")
            }
        }
    }
}

// MARK: - Configuration

private struct E2ETestConfiguration: Sendable {
    let endpointURL: URL
    let environment: [String: String]
    let port: Int
    let mcpPath: String

    static func isEnabled(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["SPEAK_TO_USER_MCP_E2E"] == "1"
    }

    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Self {
        let sourceURL = ServerSettings.repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .standardizedFileURL

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw E2ETestError("SpeakSwiftly source checkout was not found at '\(sourceURL.path)'.")
        }

        let port = try pickFreePort()
        let mcpPath = "/mcp"
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftlyMCP-E2E-\(UUID().uuidString)", isDirectory: true)
        let profileRoot = root.appendingPathComponent("profiles", isDirectory: true)
        let logDirectory = root.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        var resolvedEnvironment = environment
        resolvedEnvironment["SPEAK_TO_USER_MCP_HOST"] = "127.0.0.1"
        resolvedEnvironment["SPEAK_TO_USER_MCP_PORT"] = String(port)
        resolvedEnvironment["SPEAK_TO_USER_MCP_MCP_PATH"] = mcpPath
        resolvedEnvironment["SPEAK_TO_USER_MCP_SPEAKSWIFTLY_SOURCE_PATH"] = sourceURL.path
        resolvedEnvironment["SPEAK_TO_USER_MCP_SPEAKSWIFTLY_PROFILE_ROOT"] = profileRoot.path
        resolvedEnvironment["SPEAK_TO_USER_MCP_LOG_DIRECTORY"] = logDirectory.path
        resolvedEnvironment["SPEAK_TO_USER_MCP_XCODE_BUILD_CONFIGURATION"] = "Debug"
        resolvedEnvironment["SPEAKSWIFTLY_PROFILE_ROOT"] = profileRoot.path
        resolvedEnvironment["SPEAKSWIFTLY_SILENT_PLAYBACK"] = "1"

        return Self(
            endpointURL: URL(string: "http://127.0.0.1:\(port)\(mcpPath)")!,
            environment: resolvedEnvironment,
            port: port,
            mcpPath: mcpPath
        )
    }
}

// MARK: - Server Process

private final class ServerProcess: @unchecked Sendable {
    private enum Environment {
        static let dyldFrameworkPath = "DYLD_FRAMEWORK_PATH"
    }

    private let process: Process
    private let recorder: ProcessRecorder
    private let stdoutTask: Task<Void, Never>
    private let stderrTask: Task<Void, Never>

    init(configuration: E2ETestConfiguration) throws {
        process = Process()
        recorder = ProcessRecorder()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let executableURL = try Self.serverExecutableURL()
        let executableDirectory = executableURL.deletingLastPathComponent()

        process.executableURL = executableURL
        process.currentDirectoryURL = executableDirectory
        var environment = configuration.environment
        environment[Environment.dyldFrameworkPath] = executableDirectory.path
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let recorder = self.recorder
        stdoutTask = Self.captureLines(
            from: stdoutPipe.fileHandleForReading,
            append: { line in
                await recorder.appendStdout(line)
            }
        )
        stderrTask = Self.captureLines(
            from: stderrPipe.fileHandleForReading,
            append: { line in
                await recorder.appendStderr(line)
            }
        )

        try process.run()
    }

    func stop() async {
        if process.isRunning {
            process.terminate()
            try? await waitForExit(timeout: .seconds(5))
        }

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            try? await waitForExit(timeout: .seconds(5))
        }

        stdoutTask.cancel()
        stderrTask.cancel()
    }

    func diagnostics() async -> String {
        await recorder.diagnostics()
    }

    var isRunning: Bool {
        process.isRunning
    }

    func waitForExit(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while process.isRunning, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }

        guard !process.isRunning else {
            throw E2ETestError(
                "The SpeakSwiftlyMCP server process did not exit before the timeout expired.\n\(await diagnostics())"
            )
        }
    }

    private static func serverExecutableURL(fileManager: FileManager = .default) throws -> URL {
        let packageRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let derivedDataURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyMCP-xcodebuild-e2e-dd", isDirectory: true)
        let sourcePackagesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyMCP-xcodebuild-e2e-spm", isDirectory: true)

        try buildServerProduct(
            packageRootURL: packageRootURL,
            derivedDataURL: derivedDataURL,
            sourcePackagesURL: sourcePackagesURL
        )

        let productsURL = derivedDataURL
            .appendingPathComponent("Build/Products/Debug", isDirectory: true)
        let executableURL = productsURL.appendingPathComponent("SpeakSwiftlyMCP", isDirectory: false)
        let metallibURL = productsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw E2ETestError(
                "The Xcode-built SpeakSwiftlyMCP executable was expected at '\(executableURL.path)', but no executable was found after `xcodebuild` finished."
            )
        }

        guard fileManager.fileExists(atPath: metallibURL.path) else {
            throw E2ETestError(
                "The MLX Metal shader bundle was not found at '\(metallibURL.path)' after the Xcode-backed build completed. The optional real e2e suite cannot run without `default.metallib`."
            )
        }

        return executableURL
    }

    private static func buildServerProduct(
        packageRootURL: URL,
        derivedDataURL: URL,
        sourcePackagesURL: URL
    ) throws {
        let process = Process()
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyMCP-xcodebuild-e2e.log", isDirectory: false)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        process.currentDirectoryURL = packageRootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "build",
            "-scheme", "SpeakSwiftlyMCP",
            "-destination", "platform=macOS",
            "-derivedDataPath", derivedDataURL.path,
            "-clonedSourcePackagesDirPath", sourcePackagesURL.path,
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = try Data(contentsOf: logURL)
            let output = String(decoding: outputData, as: UTF8.self)
            throw E2ETestError(
                "The Xcode-backed SpeakSwiftlyMCP build failed with status \(process.terminationStatus). `xcodebuild` output:\n\(output)"
            )
        }
    }

    private static func captureLines(
        from fileHandle: FileHandle,
        append: @escaping @Sendable (String) async -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            var buffer = Data()

            while !Task.isCancelled {
                let data = fileHandle.availableData
                guard data.isEmpty == false else { break }
                buffer.append(data)

                while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer[..<newlineRange.lowerBound]
                    if let line = String(data: lineData, encoding: .utf8) {
                        await append(line)
                    }
                    buffer.removeSubrange(..<newlineRange.upperBound)
                }
            }

            if buffer.isEmpty == false, let line = String(data: buffer, encoding: .utf8) {
                await append(line)
            }
        }
    }
}

private actor ProcessRecorder {
    private var stdoutLines = [String]()
    private var stderrLines = [String]()
    private let maxLines = 200

    func appendStdout(_ line: String) {
        append(line, to: &stdoutLines)
    }

    func appendStderr(_ line: String) {
        append(line, to: &stderrLines)
    }

    func diagnostics() -> String {
        """
        stdout:
        \(stdoutLines.joined(separator: "\n"))

        stderr:
        \(stderrLines.joined(separator: "\n"))
        """
    }

    private func append(_ line: String, to storage: inout [String]) {
        storage.append(line)
        if storage.count > maxLines {
            storage.removeFirst(storage.count - maxLines)
        }
    }
}

// MARK: - Progress Recorder

// MARK: - Locking

private let modelLoadingLockPath = "/tmp/speak-to-user-mcp-model-loading-e2e.lock"

private func withExclusiveModelLoadingLock<T>(
    timeout: Duration = .seconds(30),
    _ body: () async throws -> T
) async throws -> T {
    let lock = try await ExclusiveModelLoadingLock.acquire(timeout: timeout)
    defer { lock.release() }
    return try await body()
}

private final class ExclusiveModelLoadingLock: @unchecked Sendable {
    private var fileDescriptor: Int32?

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        release()
    }

    static func acquire(timeout: Duration) async throws -> ExclusiveModelLoadingLock {
        FileManager.default.createFile(atPath: modelLoadingLockPath, contents: nil)
        let descriptor = open(modelLoadingLockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw E2ETestError("Could not open the exclusive model-loading lock at '\(modelLoadingLockPath)'.")
        }

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return ExclusiveModelLoadingLock(fileDescriptor: descriptor)
            }

            let code = errno
            guard code == EWOULDBLOCK else {
                close(descriptor)
                throw E2ETestError(
                    "Could not lock '\(modelLoadingLockPath)' for exclusive SpeakSwiftly e2e use (errno \(code))."
                )
            }

            if clock.now >= deadline {
                close(descriptor)
                throw E2ETestError(
                    "Timed out waiting for the exclusive model-loading lock at '\(modelLoadingLockPath)'. Another SpeakSwiftly-backed test or debug run is already in progress."
                )
            }

            try await Task.sleep(for: .milliseconds(500))
        }
    }

    func release() {
        guard let descriptor = fileDescriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        fileDescriptor = nil
    }
}

// MARK: - Running Server

private func withRunningServer<T>(
    configuration: E2ETestConfiguration,
    _ body: (URL, ServerProcess) async throws -> T
) async throws -> T {
    let process = try ServerProcess(configuration: configuration)
    do {
        try await waitUntilHealthEndpointResponds(configuration: configuration, process: process)
        let result = try await body(configuration.endpointURL, process)
        await process.stop()
        return result
    } catch {
        let diagnostics = await process.diagnostics()
        await process.stop()
        throw E2ETestError("\(error.localizedDescription)\n\(diagnostics)")
    }
}

// MARK: - MCP Helpers

private func withClient<T>(
    url: URL,
    _ body: (Client) async throws -> T
) async throws -> T {
    let client = Client(name: "SpeakSwiftlyMCPTests", version: "0.1.0")
    let transport = HTTPClientTransport(endpoint: url, streaming: false)
    _ = try await client.connect(transport: transport)
    do {
        let result = try await body(client)
        await client.disconnect()
        return result
    } catch {
        await client.disconnect()
        throw error
    }
}

private func waitUntilHealthEndpointResponds(
    configuration: E2ETestConfiguration,
    process: ServerProcess,
    timeout: Duration = .seconds(1_200)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var lastError: (any Error)?
    let healthURL = URL(string: "http://127.0.0.1:\(configuration.port)/healthz")!

    while clock.now < deadline {
        if process.isRunning == false {
            throw E2ETestError("The SpeakSwiftlyMCP server process exited before it became reachable.")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: healthURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            if statusCode == 200, String(decoding: data, as: UTF8.self) == "ok" {
                return
            }
        } catch {
            lastError = error
        }

        try await Task.sleep(for: .seconds(1))
    }

    throw E2ETestError(
        "Timed out waiting for the health endpoint to respond. Last health-check error: \(lastError?.localizedDescription ?? "none")"
    )
}

private func callTool<Output: Decodable>(
    _ name: String,
    arguments: [String: Value]?,
    meta: Metadata? = nil,
    using client: Client,
    as type: Output.Type
) async throws -> Output {
    let result = try await client.callTool(name: name, arguments: arguments, meta: meta)
    guard result.isError != true else {
        throw E2ETestError("Tool '\(name)' returned an MCP error result instead of success content.")
    }

    let payload = try firstTextContent(from: result.content)
    return try JSONDecoder().decode(Output.self, from: Data(payload.utf8))
}

private func readResource<Output: Decodable>(
    _ uri: String,
    using client: Client,
    as type: Output.Type
) async throws -> Output {
    let contents = try await client.readResource(uri: uri)
    guard let payload = contents.first?.text else {
        throw E2ETestError("Resource '\(uri)' did not return JSON text content.")
    }
    return try JSONDecoder().decode(Output.self, from: Data(payload.utf8))
}

private func firstTextContent(from content: [Tool.Content]) throws -> String {
    guard let first = content.first else {
        throw E2ETestError("The tool returned no content items to decode.")
    }

    guard case .text(let text, _, _) = first else {
        throw E2ETestError("The tool returned '\(first)' instead of text content.")
    }

    return text
}

private func text(from content: Prompt.Message.Content?) -> String? {
    guard let content else { return nil }
    guard case .text(let text) = content else { return nil }
    return text
}

private func eventually<T>(
    timeout: Duration,
    pollInterval: Duration,
    _ operation: () async throws -> T?
) async throws -> T {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var lastError: (any Error)?

    while clock.now < deadline {
        do {
            if let value = try await operation() {
                return value
            }
        } catch {
            lastError = error
        }

        try await Task.sleep(for: pollInterval)
    }

    if let lastError {
        throw lastError
    }

    throw E2ETestError("Timed out waiting for the end-to-end condition to become true.")
}

private func step<T>(
    _ name: String,
    _ operation: () async throws -> T
) async throws -> T {
    do {
        return try await operation()
    } catch {
        throw E2ETestError("End-to-end step '\(name)' failed: \(error.localizedDescription)")
    }
}

private func pickFreePort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw E2ETestError("Could not create a local TCP socket to pick a free port.")
    }
    defer { close(descriptor) }

    var reuseAddress: Int32 = 1
    setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_REUSEADDR,
        &reuseAddress,
        socklen_t(MemoryLayout.size(ofValue: reuseAddress))
    )

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        throw E2ETestError("Could not bind a local TCP socket to pick a free port.")
    }

    var resolvedAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &resolvedAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        throw E2ETestError("Could not read back the free TCP port chosen for end-to-end testing.")
    }

    return Int(UInt16(bigEndian: resolvedAddress.sin_port))
}

// MARK: - Errors

private struct E2ETestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
