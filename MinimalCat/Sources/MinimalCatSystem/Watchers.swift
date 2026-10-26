import AppKit
import MinimalCatCore

/// Tells the engine which window has focus, so a tap of the cat key can go back.
@MainActor
public final class FocusWatcher {
    private let changed: (WindowID) -> Void
    private var observer: AXObserver?
    private var token: NSObjectProtocol?

    public init(changed: @escaping (WindowID) -> Void) { self.changed = changed }

    public func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { app.map { self?.watch($0.processIdentifier) } }
        }
        NSWorkspace.shared.frontmostApplication.map { watch($0.processIdentifier) }
    }

    public func stop() {
        token.map { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        token = nil
        drop()
    }

    private func watch(_ pid: pid_t) {
        drop()
        let app = AXUIElement.app(pid)
        report(app)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.report(element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func report(_ element: AXUIElement) {
        let window = element.windowID != nil ? element : element.element(kAXFocusedWindowAttribute)
        if let id = window?.windowID { changed(WindowID(id)) }
    }

    private func drop() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }
}

/// Saves the layout while the monitors are steady, and asks for a restore once they settle after a change,
/// a wake or an unlock. It never saves while monitors come and go.
@MainActor
public final class DisplayWatcher {
    public enum State: Equatable { case steady, frozen, settling }

    public static let saveEvery: TimeInterval = 10
    public static let settleFor: TimeInterval = 1

    public private(set) var state = State.steady
    private let save: () -> Void
    private let restore: () -> Void
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var saver: Timer?
    private var settle: Timer?
    private var lastSample: [Display] = []

    public init(save: @escaping () -> Void, restore: @escaping () -> Void) {
        self.save = save
        self.restore = restore
    }

    public func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let freezes: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification), (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification)
        ]
        let changes: [(NotificationCenter, Notification.Name)] = [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (workspace, NSWorkspace.didWakeNotification), (workspace, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification)
        ]
        for (center, name) in freezes {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.freeze() }
            }))
        }
        for (center, name) in changes {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            }))
        }
        saver = Timer.scheduledTimer(withTimeInterval: Self.saveEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.state == .steady { self?.save() } }
        }
    }

    public func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens = []
        saver?.invalidate()
        settle?.invalidate()
        state = .steady
    }

    private func freeze() {
        state = .frozen
        settle?.invalidate()
    }

    private func changed() {
        state = .settling
        lastSample = Displays.current()
        settle?.invalidate()
        settle = Timer.scheduledTimer(withTimeInterval: Self.settleFor, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    /// Steady means the same displays, with real sizes, in two samples a second apart.
    private func sample() {
        let now = Displays.current()
        defer { lastSample = now }
        guard !now.isEmpty, now == lastSample, now.allSatisfy({ $0.frame.width > 1 && $0.frame.height > 1 }) else {
            return
        }
        settle?.invalidate()
        state = .steady
        restore()
    }
}
