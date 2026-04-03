import Foundation
import Hummingbird
import Logging
import MCP

// MARK: - Entry Point

@main
enum SpeakSwiftlyMCPMain {
    static func main() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        let settings = ServerSettings.fromEnvironment()
        let logger = Logger(label: "com.galew.speakswiftly-mcp")
        let owner = SpeakSwiftlyOwner(settings: settings, logger: logger)
        let transport = StatefulHTTPServerTransport(logger: logger)
        let server = await MCPServerFactory.buildServer(
            settings: settings,
            owner: owner,
            logger: logger
        )
        let app = try makeApplication(
            settings: settings,
            transport: transport,
            logger: logger
        )

        await owner.initialize()

        do {
            try await server.start(transport: transport)
            try await app.runService()
            await server.stop()
            await owner.shutdown()
        } catch {
            await server.stop()
            await owner.shutdown()
            throw error
        }
    }

    // MARK: - Application

    private static func makeApplication(
        settings: ServerSettings,
        transport: StatefulHTTPServerTransport,
        logger: Logger
    ) throws -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        let mcpPath = RouterPath(settings.mcpPath)

        router.get(mcpPath) { request, _ in
            let httpRequest = try await HTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try HTTPBridge.makeResponse(from: response)
        }

        router.post(mcpPath) { request, _ in
            let httpRequest = try await HTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try HTTPBridge.makeResponse(from: response)
        }

        router.delete(mcpPath) { request, _ in
            let httpRequest = try await HTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try HTTPBridge.makeResponse(from: response)
        }

        router.get("/healthz") { _, _ in
            Response(
                status: .ok,
                body: ResponseBody(byteBuffer: HTTPBridge.byteBuffer(from: Data("ok".utf8)))
            )
        }

        return Application(
            responder: router.buildResponder(),
            configuration: .init(
                address: .hostname(settings.host, port: settings.port),
                serverName: "SpeakSwiftlyMCP"
            ),
            logger: logger
        )
    }
}
