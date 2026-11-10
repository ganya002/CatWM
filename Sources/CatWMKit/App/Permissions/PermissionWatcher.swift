import AppKit
import SwiftUI

package final class PermissionWatcher {
    package static let shared = PermissionWatcher()
    package let atLaunch: Set<Permission>
    package private(set) var granted: Set<Permission> = []
    private let read: () -> Set<Permission>
    private let refreshScreenRecording: () -> Void
    private let queue = DispatchQueue(label: "catwm.permissions", qos: .utility)
    private var checking = false
    private var checkAgain = false
    private var timer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var subscribers: [(_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void] = []

    private static func check() -> Set<Permission> { Set(Permission.allCases.filter(\.isGranted)) }

    package init(read: @escaping () -> Set<Permission> = { PermissionWatcher.check() },
                 refreshScreenRecording: @escaping () -> Void = { ScreenRecording.shared.refresh() }) {
        self.read = read
        self.refreshScreenRecording = refreshScreenRecording
        atLaunch = read()
    }

    deinit { stop() }

    package func stop() {
        timer?.invalidate()
        timer = nil
        if let accessibilityObserver { DistributedNotificationCenter.default().removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        subscribers = []
    }

    package func start() {
        guard timer == nil else { return }
        granted = read()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.tick() }
        }
    }

    package func subscribe(_ subscriber: @escaping (_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void) {
        subscribers.append(subscriber)
    }

    package func tick() {
        guard !checking else { checkAgain = true; return }
        refreshScreenRecording()
        checking = true
        queue.async { [read, weak self] in
            let now = read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                let changed = now.symmetricDifference(self.granted)
                self.granted = now
                self.subscribers.forEach { $0(now, changed) }
                if self.checkAgain {
                    self.checkAgain = false
                    self.tick()
                }
            }
        }
    }
}
