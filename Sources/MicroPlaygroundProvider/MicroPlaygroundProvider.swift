import Vapor
import Service

public class MicroPlaygroundProvider: Provider {

    let socketPath: String
    var logger: Logger?
    public weak var delegate: MicroPlaygroundDelegate?

    public init(path: String = "playground") {
        socketPath = path
    }

    public func register(_ services: inout Services) throws {
        /// Register websocket server
        let wss = NIOWebSocketServer.default()
        wss.get(socketPath) { socket, _ in
            // TODO: security / limiting to host
            self.createPlayground(for: socket)
        }
        services.register(wss, as: WebSocketServer.self)
    }

    public func didBoot(_ container: Container) throws -> EventLoopFuture<Void> {
        self.logger = try container.make(Logger.self)
        return .done(on: container)
    }

    private func createPlayground(for socket: WebSocket) {
        let playground = MicroPlayground(DirectoryConfig.detect().workDir)
        socket.onText { socket, text in
            self.runCode(text, playground, on: socket)
        }
        delegate?.microPlayground(playground, createdFor: socket)
    }

    private func runCode(_ code: String, _ playground: MicroPlayground,
                         on socket: WebSocket) {
        delegate?.microPlayground(playground, willRun: code)
        playground.run(code: code) { [weak socket] result in
            try? self.sendJSONFormatted(result, through: socket)
            self.delegate?.microPlayground(playground, didRun: code)
        }
    }

    private func sendJSONFormatted<T: Encodable>(_ result: T,
                                                 through socket: WebSocket?) throws {
        let encoded = try JSONEncoder().encode(result)
        guard let jsonString = String(data: encoded, encoding: .utf8) else { return }
        socket?.send(jsonString)
    }

}
