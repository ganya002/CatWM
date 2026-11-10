import AppKit
package final class DockBadgeSource: NotificationSource {
    package let name = "dock"
    package static let interval: TimeInterval = 10
    package static let soon: TimeInterval = 0.5
    private weak var sink: NotificationSink?
    private let queue = DispatchQueue(label: "catwm.notifications.dock", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var reported: [String: Badge] = [:]
    private var items: [(element: AXUIElement, app: String)] = []
    private var bundles: [String: String] = [:]
    private var polled: [String: Badge] = [:]
    private var stale = true
    private var passes = 0
    private var nudged = false

    package func start(_ sink: NotificationSink) {
        self.sink = sink
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { self?.stale = true }
            }
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.pollSoon() })
        observers += [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true)]
            .map { name, awake in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    awake ? self?.resume() : self?.pause()
                }
            }
        resume()
    }

    package func stop() {
        sink = nil
        pause()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        reported = [:]
        queue.async { [weak self] in
            self?.items = []
            self?.polled = [:]
            self?.stale = true
        }
    }

    private func resume() {
        guard sink != nil, timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    package func pollSoon() {
        guard sink != nil, timer != nil else { return }
        queue.async { [weak self] in
            guard let self, !self.nudged else { return }
            self.nudged = true
            self.queue.asyncAfter(deadline: .now() + Self.soon) {
                self.nudged = false
                self.poll()
            }
        }
    }

    private func pause() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        passes += 1
        if stale || items.isEmpty || passes.isMultiple(of: 3) { items = appItems(); stale = false }
        var badges: [String: Badge] = [:]
        for item in items {
            var label: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(item.element, "AXStatusLabel" as CFString, &label)
            if result == .invalidUIElement || result == .cannotComplete { stale = true }
            if let badge = Badge(label: label as? String) { badges[item.app] = badge }
        }
        guard badges != polled else { return }
        polled = badges
        DispatchQueue.main.async { [weak self] in self?.publish(badges) }
    }

    private func appItems() -> [(element: AXUIElement, app: String)] {
        Self.dockItems().compactMap { item in
            var values: CFArray?
            let attributes = ["AXSubrole", "AXURL"] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, [], &values) == .success,
                  let list = values as? [Any], list.count == 2, list[0] as? String == "AXApplicationDockItem",
                  let url = list[1] as? URL, let app = bundle(of: url) else { return nil }
            return (item, app)
        }
    }

    private func publish(_ badges: [String: Badge]) {
        guard let sink else { return }
        for app in reported.keys where badges[app] == nil { sink.report(app: app, nil, from: name) }
        for (app, badge) in badges where reported[app] != badge { sink.report(app: app, badge, from: name) }
        reported = badges
    }

    private func bundle(of url: URL) -> String? {
        if let known = bundles[url.path] { return known }
        let id = Bundle(url: url)?.bundleIdentifier
        bundles[url.path] = id
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
