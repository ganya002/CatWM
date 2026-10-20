import Foundation

enum DesktopTransitionError: LocalizedError {
    case check(String)
    var errorDescription: String? {
        switch self {
        case .check(let message): message
        }
    }
}

@MainActor func poll(_ seconds: TimeInterval, every nanoseconds: UInt64 = 5_000_000,
                     until condition: () -> Bool) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !condition() {
        guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
    return true
}
