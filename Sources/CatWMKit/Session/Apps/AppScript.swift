import AppKit
import CoreServices
import os

package enum Blocking {
    package static func run<T: Sendable>(timeout: TimeInterval, fallback: T,
                                         _ work: @escaping @Sendable () -> T) async -> T {
        let gate = Gate<T>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            DispatchQueue.global(qos: .userInitiated).async { gate.resume(work()) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { gate.resume(fallback) }
        }
    }

    private struct GateState<T: Sendable>: Sendable {
        package var continuation: CheckedContinuation<T, Never>?
        package var done = false
    }

    private final class Gate<T: Sendable>: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: GateState<T>())

        package func install(_ continuation: CheckedContinuation<T, Never>) {
            state.withLock { $0.continuation = continuation }
        }

        package func resume(_ value: T) {
            let waiting = state.withLock { state -> CheckedContinuation<T, Never>? in
                guard !state.done else { return nil }
                state.done = true
                defer { state.continuation = nil }
                return state.continuation
            }
            waiting?.resume(returning: value)
        }
    }
}

package enum Automation {
    package enum Access: Equatable, Sendable {
        case granted, denied, needsConsent, notRunning
    }

    package static func access(_ bundleID: String, ask: Bool, timeout: TimeInterval) async -> Access {
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

package enum AppScript {
    package enum Language: String {
        case appleScript = "AppleScript"
        case javaScript = "JavaScript"
    }

    package static func run(_ source: String, language: Language, arguments: [String] = [],
                            timeout: TimeInterval) async -> String? {
        await Blocking.run(timeout: timeout + 0.5, fallback: nil) {
            execute(source, language: language, arguments: arguments, timeout: timeout)
        }
    }

    private static func execute(_ source: String, language: Language, arguments: [String],
                                timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", language.rawValue, "-e", source] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
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
