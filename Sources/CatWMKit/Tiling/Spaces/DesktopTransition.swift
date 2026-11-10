import Foundation
import QuartzCore

package enum DesktopTransitionError: LocalizedError {
    case check(String)
    case occupied
    package var errorDescription: String? {
        switch self {
        case .check(let message): message
        case .occupied: "Move all windows out of the Desktop before removing it"
        }
    }
}

@MainActor package func poll(_ seconds: TimeInterval, every nanoseconds: UInt64 = 5_000_000,
                             while current: () -> Bool = { true }, until condition: () -> Bool) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while current() {
        if condition() { return true }
        guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
        try? await Task.sleep(nanoseconds: nanoseconds) // style-ok: window server state has no change event
    }
    return false
}

@MainActor package final class DesktopTransitionTiming {
    private let start: CFTimeInterval
    private var previous: CFTimeInterval
    private var phases: [String] = []
    private var moved = false

    package init(since start: CFTimeInterval) { self.start = start; previous = start }

    package func checkpoint(_ phase: String) {
        let now = CACurrentMediaTime()
        phases.append(String(format: "%@ %.2f", phase, (now - previous) * 1000))
        previous = now
    }

    package func motion() {
        guard !moved else { return }
        moved = true
        checkpoint("frame")
        Log.info(String(format: "native workspaces: request to motion %.2f ms (%@)",
                        (previous - start) * 1000, phases.joined(separator: ", ")))
    }
}
