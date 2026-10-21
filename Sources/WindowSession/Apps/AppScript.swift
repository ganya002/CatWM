import AppKit
import CoreServices

enum Blocking {
    static func run<T: Sendable>(timeout: TimeInterval, fallback: T, _ work: @escaping @Sendable () -> T) async -> T {
        let gate = Gate<T>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            DispatchQueue.global(qos: .userInitiated).async { gate.resume(work()) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { gate.resume(fallback) }
        }
    }

    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        private var done = false

        func install(_ continuation: CheckedContinuation<T, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func resume(_ value: T) {
            let waiting: CheckedContinuation<T, Never>? = lock.withLock {
                guard !done else { return nil }
                done = true
                defer { continuation = nil }
                return continuation
            }
            waiting?.resume(returning: value)
        }
    }
}

public enum Automation {
    public enum Access: Equatable, Sendable {
        case granted, denied, needsConsent, notRunning
    }

    public static func access(_ bundleID: String, ask: Bool, timeout: TimeInterval) async -> Access {
        await Blocking.run(timeout: timeout, fallback: .needsConsent) { check(bundleID, ask: ask) }
    }

    private static func check(_ bundleID: String, ask: Bool) -> Access {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return .denied }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .needsConsent
        case OSStatus(procNotFound): return .notRunning
        default: return .denied
        }
    }
}

enum AppScript {
    enum Language: String {
        case appleScript = "AppleScript"
        case javaScript = "JavaScript"
    }

    static func run(_ source: String, language: Language, arguments: [String] = [],
                    timeout: TimeInterval) async -> String? {
        await ExternalCommand.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                                  ["-l", language.rawValue, "-e", source] + arguments, timeout: timeout)
    }
}

enum ExternalCommand {
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async -> String? {
        await Blocking.run(timeout: timeout + 0.5, fallback: nil) {
            execute(executable, arguments, timeout: timeout)
        }
    }

    private static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AppLaunch {
    static func open(_ appURL: URL, bundleID: String, arguments: [String]) async -> Bool {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        guard running, let executable = Bundle(url: appURL)?.executableURL else {
            return await Launcher.launch(appURL, arguments: arguments)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        return true
    }
}
