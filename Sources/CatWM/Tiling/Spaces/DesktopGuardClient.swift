import AppKit

@MainActor final class DesktopGuardClient {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    private var heartbeat: Timer?
    private var retainedReader: FileHandle?
    private var reply = DesktopGuardReply()
    private var launched = false, contextID = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private static var warm: DesktopGuardClient?

    static func acquire() -> DesktopGuardClient {
        defer { warm = nil }
        if let warm, warm.process.isRunning { return warm }
        return DesktopGuardClient()
    }

    static func prewarm() {
        guard warm?.process.isRunning != true else { return }
        let client = DesktopGuardClient()
        if (try? client.launch()) != nil { warm = client }
    }

    private func launch() throws {
        guard !launched else { return }
        launched = true
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--native-desktop-guard", String(getpid())]
        let descriptor = fcntl(input.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw DesktopTransitionError.check("Cannot retain the guard pipe") }
        retainedReader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        process.standardInput = input
        process.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
        try process.run()
    }

    func start(_ context: DesktopGuard.Context) async throws {
        try launch()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.send("PING")
            }
        }
        heartbeat = timer
        RunLoop.main.add(timer, forMode: .common)
        do {
            try await wait { self.reply.ready }
            try await update(context)
        } catch {
            heartbeat?.invalidate()
            if process.isRunning { process.terminate() }
            throw error
        }
    }

    func update(_ context: DesktopGuard.Context) async throws {
        contextID += 1
        let id = contextID
        send("CONTEXT \(id) " + (try JSONEncoder().encode(context).base64EncodedString()))
        try await wait { self.reply.context >= id || !self.process.isRunning }
        guard reply.context >= id else { throw DesktopTransitionError.check("Desktop recovery process stopped") }
    }

    func restore() async throws {
        let id = contextID
        send("RESTORE \(id)")
        try await wait { self.reply.restoreSubmitted >= id || !self.process.isRunning }
        guard reply.restoreSubmitted >= id else {
            throw DesktopTransitionError.check("Desktop recovery process stopped")
        }
    }

    func finish() async throws {
        let id = contextID
        send("RELEASE \(id)")
        try await wait { self.reply.released >= id || !self.process.isRunning }
        guard reply.released >= id, process.isRunning else {
            throw DesktopTransitionError.check("Desktop recovery process stopped")
        }
        heartbeat?.invalidate()
        heartbeat = nil
        if Self.warm?.process.isRunning != true {
            Self.warm = self
        } else if Self.warm !== self {
            send("DONE")
            try await wait { self.reply.finished && !self.process.isRunning }
            output.fileHandleForReading.readabilityHandler = nil
            retainedReader = nil
        }
    }

    private func send(_ message: String) {
        guard process.isRunning else { heartbeat?.invalidate(); return }
        try? input.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
    }

    private func receive(_ data: Data) {
        defer { wake() }
        if data.isEmpty { output.fileHandleForReading.readabilityHandler = nil; return }
        reply.receive(String(data: data, encoding: .utf8) ?? "")
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw DesktopTransitionError.check("Desktop restore guard handshake timed out")
            }
            await withCheckedContinuation { continuation in
                waiting.append(continuation)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { [weak self] in
                    MainActor.assumeIsolated { self?.wake() }
                }
            }
        }
    }

    private func wake() {
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume() }
    }
}

struct DesktopGuardReply {
    private(set) var ready = false, finished = false, context = 0
    private(set) var released = -1
    private(set) var restoreSubmitted = -1
    private var buffer = ""

    mutating func receive(_ text: String) {
        buffer += text
        while let end = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<end])
            buffer.removeSubrange(...end)
            if line == "READY" { ready = true }
            if line == "DONE" { finished = true }
            if line.hasPrefix("CONTEXT_READY "), let id = Int(line.dropFirst(14)) { context = max(context, id) }
            if line.hasPrefix("RELEASED "), let id = Int(line.dropFirst(9)) { released = max(released, id) }
            if line.hasPrefix("RESTORE_SUBMITTED "), let id = Int(line.dropFirst(18)) {
                restoreSubmitted = max(restoreSubmitted, id)
            }
        }
    }
}
