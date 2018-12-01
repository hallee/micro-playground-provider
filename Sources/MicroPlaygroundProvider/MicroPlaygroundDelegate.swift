import Vapor

public protocol MicroPlaygroundDelegate: AnyObject {
    func microPlayground(_ playground: MicroPlayground, didRun code: String)
    func microPlayground(_ playground: MicroPlayground, createdFor socket: WebSocket)
}

// Make the delegate methods optional by providing an empty implementation
extension MicroPlaygroundDelegate {
    func microPlayground(_ playground: MicroPlayground, didRun code: String) { }
    func microPlayground(_ playground: MicroPlayground, createdFor socket: WebSocket) { }
}
