import AppKit
import SwiftUI

final class PermissionWatcher {
    static let shared = PermissionWatcher()
    let atLaunch = PermissionWatcher.check()
    private(set) var granted: Set<Permission> = []
    private var timer: Timer?
    private var subscribers: [(_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void] = []

    private static func check() -> Set<Permission> { Set(Permission.allCases.filter(\.isGranted)) }

    func start() {
        guard timer == nil else { return }
        granted = Self.check()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func subscribe(_ f: @escaping (_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void) {
        subscribers.append(f)
    }

    private func tick() {
        let now = Self.check()
        let changed = now.symmetricDifference(granted)
        granted = now
        subscribers.forEach { $0(now, changed) }
    }
}
