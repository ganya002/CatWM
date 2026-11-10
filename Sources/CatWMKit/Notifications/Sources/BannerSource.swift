import AppKit
package final class BannerSource: NotificationSource {
    package let name: String
    package let messagesClearOnFocus = true
    package let reportsMessages: Bool
    package static let bundleID = "com.apple.notificationcenterui"
    package static let subroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    private weak var sink: NotificationSink?
    private let queue = DispatchQueue(label: "catwm.notifications.banner", qos: .utility)
    private var observer: AXObserver?
    private var launch: NSObjectProtocol?
    private var seen: [String: Date] = [:]
    package var changed: () -> Void = {}

    package init(reportsMessages: Bool) {
        self.reportsMessages = reportsMessages
        name = reportsMessages ? "banner" : "banner.trigger"
    }

    package var isAvailable: Bool { reportsMessages != NotificationDatabase.isReadable }

    package func start(_ sink: NotificationSink) {
        self.sink = sink
        launch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Self.bundleID { self?.observe() }
        }
        observe()
    }

    package func stop() {
        sink = nil
        if let launch { NSWorkspace.shared.notificationCenter.removeObserver(launch) }
        launch = nil
        detach()
        seen = [:]
    }

    private func detach() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    private func observe() {
        detach()
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            Unmanaged<BannerSource>.fromOpaque(refcon).takeUnretainedValue().created(element)
        }
        guard AXObserverCreate(center.processIdentifier, callback, &created) == .success, let created else { return }
        let app = axApp(center.processIdentifier, timeout: 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func created(_ element: AXUIElement) {
        guard sink != nil else { return }
        guard reportsMessages else { return changed() }
        queue.async { [weak self] in
            AXUIElementSetMessagingTimeout(element, 0.5)
            guard element.string(kAXRoleAttribute) == kAXWindowRole else { return }
            let banners = Self.banners(in: element, depth: 0)
            guard !banners.isEmpty else { return }
            DispatchQueue.main.async { self?.add(banners) }
        }
    }

    private func add(_ banners: [[String]]) {
        guard let sink else { return }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 10 }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for texts in banners {
            let key = texts.joined(separator: "\n")
            guard seen[key] == nil else { continue }
            seen[key] = now
            if let message = Self.message(texts, apps: apps) { sink.add(message, from: name) }
        }
        changed()
    }
    package static func message(_ texts: [String], apps: [NSRunningApplication]) -> NotificationMessage? {
        for (index, text) in texts.enumerated() {
            guard let app = apps.first(where: { $0.localizedName == text }), let id = app.bundleIdentifier else {
                continue
            }
            let rest = texts.enumerated().filter { $0.offset != index }.map(\.element)
            return NotificationMessage(app: id, title: rest.first ?? "", subtitle: rest.dropFirst().first ?? "",
                                       body: rest.dropFirst(2).joined(separator: " "))
        }
        return nil
    }

    private static func banners(in element: AXUIElement, depth: Int) -> [[String]] {
        guard depth < 8 else { return [] }
        if let subrole = element.string(kAXSubroleAttribute), subroles.contains(subrole) {
            var texts = statics(in: element, depth: 0)
            if texts.isEmpty, let description = element.string(kAXDescriptionAttribute) {
                texts = description.components(separatedBy: ", ")
            }
            return texts.isEmpty ? [] : [texts]
        }
        return element.elements(kAXChildrenAttribute).flatMap { banners(in: $0, depth: depth + 1) }
    }

    private static func statics(in element: AXUIElement, depth: Int) -> [String] {
        guard depth < 4 else { return [] }
        if element.string(kAXRoleAttribute) == kAXStaticTextRole {
            return element.string(kAXValueAttribute).map { [$0] } ?? []
        }
        return element.elements(kAXChildrenAttribute).flatMap { statics(in: $0, depth: depth + 1) }
    }
}
