import AppKit
import SwiftUI

@MainActor package final class PermissionWatcher {
    package static let shared = PermissionWatcher(atLaunch: Permission.grantedAtLaunch)
    package let atLaunch: Set<Permission>
    package private(set) var granted: Set<Permission> = []
    private let read: @Sendable () -> Set<Permission>
    private let refreshScreenRecording: () -> Void
    private let queue = DispatchQueue(label: "catwm.permissions", qos: .utility)
    private var checking = false
    private var checkAgain = false
    private let isWatched: @MainActor () -> Bool
    private var timer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var subscribers: [(_ granted: Set<Permission>, _ changed: Set<Permission>) -> Void] = []

    private nonisolated static func check() -> Set<Permission> { Set(Permission.allCases.filter(\.isGranted)) }

    package var isPolling: Bool { timer != nil }

    private static func userIsInSettings() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return id == "com.apple.systempreferences" || id == Bundle.main.bundleIdentifier
    }

    package init(read: @escaping @Sendable () -> Set<Permission> = { PermissionWatcher.check() },
                 refreshScreenRecording: @escaping () -> Void = { ScreenRecording.shared.refresh() },
                 isWatched: @escaping @MainActor () -> Bool = { true }) {
        self.read = read
        self.refreshScreenRecording = refreshScreenRecording
        self.isWatched = isWatched
        atLaunch = read()
    }

    private init(atLaunch: Set<Permission>) {
        read = { PermissionWatcher.check() }
        refreshScreenRecording = { ScreenRecording.shared.refresh() }
        isWatched = { PermissionWatcher.userIsInSettings() }
        self.atLaunch = atLaunch
    }

    package func stop() {
        setPolling(false)
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let accessibilityObserver { DistributedNotificationCenter.default().removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        subscribers = []
    }

    package func start() {
        guard activationObserver == nil else { return }
        granted = read()
        setPolling(isWatched())
        activationObserver = NSWorkspace.shared.notificationCenter.observeOnMain(
            NSWorkspace.didActivateApplicationNotification
        ) { [weak self] in self?.appSwitched() }
        accessibilityObserver = DistributedNotificationCenter.default().observeOnMain(
            Notification.Name("com.apple.accessibility.api")
        ) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.tick() }
        }
    }

    private func setPolling(_ polling: Bool) {
        timer?.invalidate()
        timer = polling ? Timer.onMain(every: 1.5, owner: self) { $0.tick() } : nil
    }

    private func appSwitched() {
        let watched = isWatched()
        guard watched != isPolling else { return }
        setPolling(watched)
        tick()
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
