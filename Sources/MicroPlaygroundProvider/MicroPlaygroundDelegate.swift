import Vapor

public protocol MicroPlaygroundDelegate: AnyObject {
    func microPlayground(_ playground: MicroPlayground, willRun code: String)
    func microPlayground(_ playground: MicroPlayground, didRun code: String)
    func microPlayground(_ playground: MicroPlayground, createdFor socket: WebSocket)
}

// Make the delegate methods optional by providing an empty implementation
public extension MicroPlaygroundDelegate {
    public func microPlayground(_ playground: MicroPlayground, willRun code: String) { }
    public func microPlayground(_ playground: MicroPlayground, didRun code: String) { }
    public func microPlayground(_ playground: MicroPlayground, createdFor socket: WebSocket) { }
}
