import AppKit

package final class DesktopGuard {
    package struct Context: Codable {
        package let display: String
        package let source: UInt64
        package let destination: UInt64
        package let sourceOptions: UInt32
        package let destinationOptions: UInt32
        package var menuBar: DesktopMenuBar.State?

        package func restore() {
            if let menuBar {
                menuBar.restore()
                DesktopMenuBarNative.alpha(menuBar.space, -1)
            }
            let current = Spaces.current(display: display)
            let entries = [(source, sourceOptions), (destination, destinationOptions)]
            _ = DesktopBridge.setVisible(entries.map(\.0).filter { $0 != current }, false)
            for (space, options) in entries.sorted(by: { $0.0 == current && $1.0 != current }) {
                if let state = DesktopBridge.state(space), state.transform == .identity,
                   state.options == options { continue }
                _ = DesktopBridge.transform(space, x: 0, options: options)
            }
            if current == source || current == destination {
                _ = DesktopBridge.animating(display: display, active: false)
            }
        }
    }

    private var context: Context?
    private var contextID = 0
    private var watch: DispatchSourceProcess?
    private var timeout: DispatchSourceTimer?
    private var lease = DesktopGuardLease(now: ProcessInfo.processInfo.systemUptime)
    private var input = ""

    private init(parent: pid_t) {
        let watch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        watch.setEventHandler { [weak self] in self?.check(parentExited: true) }
        watch.resume()
        self.watch = watch
        let timeout = DispatchSource.makeTimerSource(queue: .main)
        timeout.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timeout.setEventHandler { [weak self] in self?.check() }
        timeout.resume()
        self.timeout = timeout
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async {
                guard !data.isEmpty else { self?.check(parentExited: true); return }
                self?.receive(data)
            }
        }
    }

    package static func run() -> Never {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let parent = pid_t(arguments[2]), parent > 1 else { exit(1) }
        guard Spaces.canMoveWindows else { exit(1) }
        let guardProcess = DesktopGuard(parent: parent)
        FileHandle.standardOutput.write(Data("READY\n".utf8))
        if kill(parent, 0) != 0 { guardProcess.check(parentExited: true) }
        withExtendedLifetime(guardProcess) { CFRunLoopRun() }
        exit(0)
    }

    private func receive(_ data: Data) {
        input += String(data: data, encoding: .utf8) ?? ""
        while let end = input.firstIndex(of: "\n") {
            let message = String(input[..<end])
            input.removeSubrange(...end)
            if message.hasPrefix("CONTEXT ") {
                let parts = message.split(separator: " ", maxSplits: 2)
                if parts.count == 3, let id = Int(parts[1]), let data = Data(base64Encoded: String(parts[2])),
                   let decoded = try? JSONDecoder().decode(Context.self, from: data),
                   lease.accept(now: ProcessInfo.processInfo.systemUptime) {
                    context = decoded
                    contextID = id
                    FileHandle.standardOutput.write(Data("CONTEXT_READY \(id)\n".utf8))
                }
                continue
            }
            if message.hasPrefix("RESTORE "), let id = Int(message.dropFirst(8)), id == contextID,
               let context, lease.accept(now: ProcessInfo.processInfo.systemUptime) {
                context.restore()
                FileHandle.standardOutput.write(Data("RESTORE_SUBMITTED \(id)\n".utf8))
                continue
            }
            if message.hasPrefix("RELEASE "), let id = Int(message.dropFirst(8)), id == contextID,
               lease.accept(now: ProcessInfo.processInfo.systemUptime) {
                context = nil
                FileHandle.standardOutput.write(Data("RELEASED \(id)\n".utf8))
                continue
            }
            if lease.receive(message, now: ProcessInfo.processInfo.systemUptime) == .finish {
                FileHandle.standardOutput.write(Data("DONE\n".utf8))
                exit(0)
            }
        }
    }

    private func check(parentExited: Bool = false) {
        guard let context else {
            if parentExited { exit(0) }
            return
        }
        guard lease.check(now: ProcessInfo.processInfo.systemUptime, parentExited: parentExited) == .restore else {
            return
        }
        context.restore()
        Log.info("native-desktop-guard: restored transforms after parent exit or missing heartbeat")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) } // style-ok: the restore applies with no event
    }
}

package struct DesktopGuardLease {
    package enum Action: Equatable { case none, restore, finish }
    package private(set) var armed = true
    private var heartbeat: TimeInterval
    private let timeout: TimeInterval = 1.5

    package init(now: TimeInterval) { heartbeat = now }

    package mutating func accept(now: TimeInterval) -> Bool {
        guard armed else { return false }
        heartbeat = now
        return true
    }

    package mutating func receive(_ message: String, now: TimeInterval) -> Action {
        guard armed else { return .none }
        if message == "PING" { heartbeat = now }
        if message == "DONE" { armed = false; return .finish }
        return .none
    }

    package mutating func check(now: TimeInterval, parentExited: Bool = false) -> Action {
        guard armed, parentExited || now - heartbeat >= timeout else { return .none }
        armed = false
        return .restore
    }
}
