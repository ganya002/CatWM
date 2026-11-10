import AppKit

package final class ControlServer {
    package static let shared = ControlServer()

    package static var socketPath: String {
        ProcessInfo.processInfo.environment["CATWM_SOCKET"]
            ?? Config.url.deletingLastPathComponent().appendingPathComponent("catwm.sock").path
    }

    package static var hello: JSON {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return ["protocol": .int(CommandRegistry.protocolVersion), "version": .string(version),
                "pid": .int(Int(getpid()))]
    }

    private let manager: WindowManager?

    package init(manager: WindowManager? = nil) { self.manager = manager }

    private let queue = DispatchQueue(label: "catwm.control.accept", qos: .userInitiated)
    private var listener: DispatchSourceRead?
    private var clients: [ObjectIdentifier: ControlConnection] = [:]

    package func start(path: String = ControlServer.socketPath) {
        guard listener == nil else { return }
        guard let descriptor = Self.listen(on: path) else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor); unlink(path) }
        listener = source
        source.resume()
        Log.info("control: listening on \(path)")
    }

    package func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [self] in
            clients.values.forEach { $0.close() }
            clients = [:]
        }
    }

    private func accept(_ listenFD: Int32) {
        let descriptor = Darwin.accept(listenFD, nil, nil)
        guard descriptor >= 0 else { return }
        let manager = self.manager
        let connection = ControlConnection(descriptor: descriptor, onLine: { connection, line in
            DispatchQueue.main.async {
                connection.send(Self.reply(to: line, client: connection, manager: manager ?? .shared))
            }
        }, onClose: { [weak self] connection in
            self?.queue.async { self?.clients[ObjectIdentifier(connection)] = nil }
            DispatchQueue.main.async { EventBus.shared.remove(connection) }
        })
        clients[ObjectIdentifier(connection)] = connection
        connection.start()
        connection.send(JSON.object(["hello": Self.hello]).encoded() + Data("\n".utf8))
    }

    package static func reply(to line: Data, client: ControlConnection?, manager: WindowManager = .shared) -> Data {
        var id = JSON.null
        let response: JSON
        do {
            guard let request = JSON.parse(line)?.object else {
                throw ControlError.badRequest("Send one JSON object")
            }
            id = request["id"] ?? .null
            guard let name = request["command"]?.string else { throw ControlError.badRequest("Send a `command`") }
            let args = request["args"] ?? [:]
            guard let given = args.object else { throw ControlError.badRequest("`args` must be an object") }
            let result = try CommandRegistry.execute(name, given, client: client, manager: manager)
            response = ["id": id, "ok": true, "result": result]
        } catch let error as ControlError {
            response = ["id": id, "ok": false,
                        "error": ["code": .string(error.code), "message": .string(error.message)]]
        } catch {
            response = ["id": id, "ok": false, "error": ["code": "failed", "message": .string("\(error)")]]
        }
        return response.encoded() + Data("\n".utf8)
    }

    package static func listen(on path: String, log: (String) -> Void = { Log.info($0) }) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            log("control: socket path is too long: \(path)")
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Array(path.utf8) + [0])
        }
        Log.attempt("control: create socket folder") {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        if Self.isAlive(address) {
            log("control: another CatWM listens on \(path)")
            return nil
        }
        unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        let previous = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previous)
        guard bound == 0, Darwin.listen(descriptor, 16) == 0 else {
            log("control: cannot listen on \(path): \(String(cString: strerror(errno)))")
            Darwin.close(descriptor)
            return nil
        }
        chmod(path, 0o600)
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var quiet: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    private static func isAlive(_ address: sockaddr_un) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
    }
}
