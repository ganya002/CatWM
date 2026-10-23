import Foundation

enum DesktopTransitionError: LocalizedError {
    case check(String)
    case occupied
    var errorDescription: String? {
        switch self {
        case .check(let message): message
        case .occupied: "Move all windows out of the Desktop before removing it"
        }
    }
}

@MainActor func poll(_ seconds: TimeInterval, every nanoseconds: UInt64 = 5_000_000,
                     while current: () -> Bool = { true }, until condition: () -> Bool) async -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while current() {
        if condition() { return true }
        guard ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return false }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
    return false
}
