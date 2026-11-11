import AppKit
import os

package final class ControlServer: Sendable {
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

    private struct State {
        var listener: DispatchSourceRead?
        var clients: [ObjectIdentifier: ControlConnection] = [:]
    }

    private let manager: WindowManager?
    private let queue = DispatchQueue(label: "catwm.control.accept", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init(manager: WindowManager? = nil) { self.manager = manager }

    package func start(path: String = ControlServer.socketPath) {
        guard state.withLock({ $0.listener == nil }) else { return }
        guard let descriptor = Self.listen(on: path) else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor); unlink(path) }
        state.withLock { $0.listener = source }
        source.resume()
        Log.info("control: listening on \(path)")
    }

    package func stop() {
        let listener = state.withLock { state in
            defer { state.listener = nil }
            return state.listener
        }
        listener?.cancel()
        queue.async { [self] in
            let closing = state.withLock { state in
                defer { state.clients = [:] }
                return Array(state.clients.values)
            }
            closing.forEach { $0.close() }
        }
    }

    private func accept(_ listenFD: Int32) {
        let descriptor = Darwin.accept(listenFD, nil, nil)
        guard descriptor >= 0 else { return }
        let manager = self.manager
        let connection = ControlConnection(descriptor: descriptor, onLine: { connection, line in
            DispatchQueue.main.async {
                Self.respond(to: line, client: connection, manager: manager ?? .shared, send: connection.send)
            }
        }, onClose: { [weak self] connection in
            self?.queue.async { [weak self] in
                self?.state.withLock { _ = $0.clients.removeValue(forKey: ObjectIdentifier(connection)) }
            }
            DispatchQueue.main.async {
                EventBus.shared.remove(connection)
                (manager ?? .shared).connectionClosed(connection)
            }
        })
        state.withLock { $0.clients[ObjectIdentifier(connection)] = connection }
        connection.start()
        connection.send(JSON.object(["hello": Self.hello]).encoded() + Data("\n".utf8))
    }

    @MainActor package static func respond(to line: Data, client: ControlConnection?, manager: WindowManager = .shared,
                                           send: @escaping (Data) -> Void) {
        func answer(_ id: JSON, _ outcome: () throws -> JSON) {
            let response: JSON
            do {
                response = ["id": id, "ok": true, "result": try outcome()]
            } catch let error as ControlError {
                response = ["id": id, "ok": false,
                            "error": ["code": .string(error.code), "message": .string(error.message)]]
            } catch {
                response = ["id": id, "ok": false, "error": ["code": "failed", "message": .string("\(error)")]]
            }
            send(response.encoded() + Data("\n".utf8))
        }
        guard let request = JSON.parse(line)?.object else {
            return answer(.null) { throw ControlError.badRequest("Send one JSON object") }
        }
        let id = request["id"] ?? .null
        do {
            guard let name = request["command"]?.string else { throw ControlError.badRequest("Send a `command`") }
            guard let given = (request["args"] ?? [:]).object else {
                throw ControlError.badRequest("`args` must be an object")
            }
            let (command, call) = try CommandRegistry.prepare(name, given, client: client, manager: manager)
            switch command.body {
            case .now(let run): answer(id) { try run(call) }
            case .later(let run):
                Task { @MainActor in
                    do {
                        let result = try await run(call)
                        answer(id) { result }
                    } catch {
                        answer(id) { throw error }
                    }
                }
            }
        } catch {
            answer(id) { throw error }
        }
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
