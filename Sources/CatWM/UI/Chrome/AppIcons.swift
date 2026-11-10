import AppKit
import CatWMKit

final class AppIcons {
    static let shared = AppIcons()
    private var cache: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        cache[pid] = icon
        return icon
    }

    func iconOrGeneric(for pid: pid_t) -> NSImage {
        icon(for: pid) ?? NSWorkspace.shared.icon(for: .application)
    }

    func prune(keeping pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) || NSRunningApplication(processIdentifier: $0.key) != nil }
    }
}
