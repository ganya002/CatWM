import AppKit
import os

@MainActor package final class DockBadgeSource: NotificationSource {
    package let name = "dock"
    package nonisolated static let interval: TimeInterval = 10
    package nonisolated static let soon: TimeInterval = 0.5
    private weak var sink: NotificationSink?
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var reported: [String: Badge] = [:]
    private var poller: DockBadgePoller?
    private var tracked: Set<String> = []

    package func start(_ sink: NotificationSink) {
        self.sink = sink
        let poller = DockBadgePoller { [weak self] badges in
            DispatchQueue.main.async { self?.publish(badges) }
        }
        self.poller = poller
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            center.observeOnMain(name) { poller.markStale() }
        }
        observers.append(center.observeOnMain(NSWorkspace.didActivateApplicationNotification) { [weak self] in
            self?.pollSoon()
        })
        observers += [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true)]
            .map { name, awake in
                center.observeOnMain(name) { [weak self] in
                    awake ? self?.resume() : self?.pause()
                }
            }
    }

    package func track(_ bundles: Set<String>) {
        guard let poller else { return }
        let added = !bundles.isSubset(of: tracked)
        tracked = bundles
        poller.track(bundles)
        if bundles.isEmpty {
            pause()
        } else if timer == nil {
            resume()
        } else if added {
            poller.pollSoon()
        }
    }

    package func stop() {
        sink = nil
        pause()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        reported = [:]
        tracked = []
        poller?.reset()
        poller = nil
    }

    private func resume() {
        guard sink != nil, timer == nil, !tracked.isEmpty, let poller else { return }
        let timer = DispatchSource.makeTimerSource(queue: poller.queue)
        timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(500))
        timer.setEventHandler { @Sendable in poller.poll() }
        timer.resume()
        self.timer = timer
    }

    package func pollSoon() {
        guard sink != nil, timer != nil else { return }
        poller?.pollSoon()
    }

    private func pause() {
        timer?.cancel()
        timer = nil
    }

    private func publish(_ badges: [String: Badge]) {
        guard let sink else { return }
        for app in reported.keys where badges[app] == nil { sink.report(app: app, nil, from: name) }
        for (app, badge) in badges where reported[app] != badge { sink.report(app: app, badge, from: name) }
        reported = badges
    }
}

private final class DockBadgePoller: Sendable {
    struct Item: Sendable { let element: AXReference<AXUIElement>, app: String }
    struct State {
        var items: [Item] = []
        var bundles: [String: String] = [:]
        var polled: [String: Badge] = [:]
        var stale = true
        var passes = 0
        var nudged = false
        var tracked: Set<String> = []
    }

    let queue = DispatchQueue(label: "catwm.notifications.dock", qos: .utility)
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let publish: @Sendable ([String: Badge]) -> Void

    init(publish: @escaping @Sendable ([String: Badge]) -> Void) { self.publish = publish }

    func markStale() { queue.async { [self] in state.withLock { $0.stale = true } } }

    func track(_ bundles: Set<String>) { queue.async { [self] in state.withLock { $0.tracked = bundles } } }

    func reset() { queue.async { [self] in state.withLock { $0 = State() } } }

    func pollSoon() {
        queue.async { [self] in
            guard state.withLock({ state in defer { state.nudged = true }; return !state.nudged }) else { return }
            queue.asyncAfter(deadline: .now() + DockBadgeSource.soon) { [self] in
                state.withLock { $0.nudged = false }
                poll()
            }
        }
    }

    func poll() {
        let (known, due, bundleCache, tracked) = state.withLock { state in
            state.passes += 1
            let due = state.stale || state.items.isEmpty || state.passes.isMultiple(of: 3)
            if due { state.stale = false }
            return (state.items, due, state.bundles, state.tracked)
        }
        var bundles = bundleCache
        let items = due ? appItems(&bundles) : known
        var badges: [String: Badge] = [:]
        var sawStale = false
        for item in items where tracked.contains(item.app) {
            var label: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(item.element.object, "AXStatusLabel" as CFString, &label)
            if result == .invalidUIElement || result == .cannotComplete { sawStale = true }
            if let badge = Badge(label: label as? String) { badges[item.app] = badge }
        }
        let (found, stale, learned) = (badges, sawStale, bundles)
        let changed = state.withLock { state in
            if due {
                state.items = items
                state.bundles = learned
            }
            if stale { state.stale = true }
            defer { state.polled = found }
            return found != state.polled
        }
        if changed { publish(found) }
    }

    private func appItems(_ bundles: inout [String: String]) -> [Item] {
        Self.dockItems().compactMap { item in
            var values: CFArray?
            let attributes = ["AXSubrole", "AXURL"] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, [], &values) == .success,
                  let list = values as? [Any], list.count == 2, list[0] as? String == "AXApplicationDockItem",
                  let url = list[1] as? URL, let app = Self.bundle(of: url, cache: &bundles) else { return nil }
            return Item(element: AXReference(item), app: app)
        }
    }

    private static func bundle(of url: URL, cache: inout [String: String]) -> String? {
        if let known = cache[url.path] { return known }
        let id = Bundle(url: url)?.bundleIdentifier
        cache[url.path] = id
        return id
    }

    private static func dockItems() -> [AXUIElement] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = axApp(dock.processIdentifier, timeout: 0.5)
        let list = app.elements(kAXChildrenAttribute).first { $0.string(kAXRoleAttribute) == kAXListRole }
        return list?.elements(kAXChildrenAttribute) ?? []
    }
}
