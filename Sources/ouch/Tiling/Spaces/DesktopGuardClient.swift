import AppKit

@MainActor final class DesktopGuardClient {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    private var heartbeat: Timer?
    private var retainedReader: FileHandle?
    private var ready = false, acknowledged = false, launched = false
    private var response = ""

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
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.send("PING") }
        }
        heartbeat = timer
        RunLoop.main.add(timer, forMode: .common)
        do {
            try await wait { self.ready }
            send("CONTEXT " + (try JSONEncoder().encode(context).base64EncodedString()))
        } catch {
            heartbeat?.invalidate()
            if process.isRunning { process.terminate() }
            throw error
        }
    }

    func finish() async throws {
        defer {
            heartbeat?.invalidate()
            output.fileHandleForReading.readabilityHandler = nil
            retainedReader = nil
        }
        send("DONE")
        try await wait { self.acknowledged && !self.process.isRunning }
    }

    private func send(_ message: String) {
        guard process.isRunning else { heartbeat?.invalidate(); return }
        try? input.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
    }

    private func receive(_ data: Data) {
        if data.isEmpty { output.fileHandleForReading.readabilityHandler = nil; return }
        response += String(data: data, encoding: .utf8) ?? ""
        ready = response.contains("READY\n")
        acknowledged = response.contains("DONE\n")
    }

    private func wait(_ condition: () -> Bool) async throws {
        guard await poll(3, until: condition) else {
            throw DesktopTransitionError.check("Desktop restore guard handshake timed out")
        }
    }
}
