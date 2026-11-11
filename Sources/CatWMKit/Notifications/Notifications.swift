import AppKit

@MainActor package final class Notifications: NotificationSink {
    package struct Change: Equatable {
        package let window: CGWindowID
        package let app: String?
        package let badge: Badge?
        package let source: String?
    }

    package struct Token: Hashable {
        package let value: Int
    }

    package static let shared = Notifications()

    package private(set) var enabled = false
    private var sources: [NotificationSource] = []
    private var running: Set<ObjectIdentifier> = []
    private var listeners: [Int: (Change) -> Void] = [:]
    private var nextToken = 0
    private var apps: [String: [String: Badge]] = [:]
    private var windows: [CGWindowID: [String: Badge]] = [:]
    private var messages: [String: [String: [NotificationMessage]]] = [:]
    private var shown: [CGWindowID: (badge: Badge, source: String)] = [:]
    private var focused: CGWindowID?
    private var known: Set<CGWindowID> = []
    private var tracked: Set<String> = []
    private var matches: [String: Matches] = [:]
    private let windowList: () -> [Window]

    package init(windowList: @escaping () -> [Window] = { Array(WindowManager.shared.windows.values) }) {
        self.windowList = windowList
    }

    package func badge(for window: CGWindowID) -> Badge? { shown[window]?.badge }

    @discardableResult
    package func listen(_ listener: @escaping (Change) -> Void) -> Token {
        nextToken += 1
        listeners[nextToken] = listener
        return Token(value: nextToken)
    }

    package func stopListening(_ token: Token) { listeners[token.value] = nil }

    package var hasSources: Bool { !sources.isEmpty }

    package func register(_ source: NotificationSource) {
        guard !sources.contains(where: { $0 === source }) else { return }
        sources.append(source)
        refreshSources()
    }

    package func unregister(_ source: NotificationSource) {
        sources.removeAll { $0 === source }
        if running.remove(ObjectIdentifier(source)) != nil { source.stop() }
        drop(source.name)
    }

    package func setEnabled(_ wanted: Bool) {
        guard wanted != enabled else { return }
        enabled = wanted
        updateTracked()
        refreshSources()
    }
    package func refreshSources() {
        for source in sources {
            let key = ObjectIdentifier(source)
            let wanted = enabled && source.isAvailable
            if wanted, running.insert(key).inserted {
                source.start(self)
                source.track(tracked)
            } else if !wanted, running.remove(key) != nil {
                source.stop()
                drop(source.name)
            }
        }
    }

    package func stateChanged(focused id: CGWindowID?) {
        var dirty = false
        if id != focused {
            focused = id
            if let id { dirty = clearOnFocus(id) }
        }
        updateTracked()
        guard enabled, !apps.isEmpty || !windows.isEmpty || !messages.isEmpty || !shown.isEmpty else { return }
        let ids = Set(windowList().map(\.id))
        if ids != known { dirty = true }
        if dirty { resolve() }
    }

    private func updateTracked() {
        let bundles = enabled ? Set(windowList().compactMap(\.bundleID)) : []
        guard bundles != tracked else { return }
        tracked = bundles
        for source in sources where running.contains(ObjectIdentifier(source)) { source.track(bundles) }
    }

    package func titleChanged(_ window: Window) {
        guard let app = window.bundleID, messages.values.contains(where: { $0[app] != nil }) else { return }
        matches[app] = nil
        resolve()
    }

    package func forget(_ id: CGWindowID) {
        guard windows.removeValue(forKey: id) != nil || shown[id] != nil || known.contains(id) else { return }
        matches = [:]
        resolve()
    }

    package func report(app: String, _ badge: Badge?, from source: String) {
        guard apps[app]?[source] != badge else { return }
        apps[app, default: [:]][source] = badge
        if apps[app]?.isEmpty == true { apps[app] = nil }
        if badge == nil { clearMessages(of: app) }
        resolve()
    }

    package func report(window: CGWindowID, _ badge: Badge?, from source: String) {
        guard windows[window]?[source] != badge else { return }
        windows[window, default: [:]][source] = badge
        if windows[window]?.isEmpty == true { windows[window] = nil }
        resolve()
    }

    package func report(messages list: [NotificationMessage], for app: String, from source: String) {
        let kept = Array(list.suffix(Self.messageLimit))
        guard messages[source]?[app] ?? [] != kept else { return }
        messages[source, default: [:]][app] = kept.isEmpty ? nil : kept
        matches[app] = nil
        resolve()
    }

    package func add(_ message: NotificationMessage, from source: String) {
        let list = messages[source]?[message.app] ?? []
        messages[source, default: [:]][message.app] = Array((list + [message]).suffix(Self.messageLimit))
        matches[message.app] = nil
        resolve()
    }

    package nonisolated static let messageLimit = 50

    private func drop(_ source: String) {
        for app in apps.keys { apps[app]?[source] = nil; if apps[app]?.isEmpty == true { apps[app] = nil } }
        for id in windows.keys { windows[id]?[source] = nil; if windows[id]?.isEmpty == true { windows[id] = nil } }
        messages[source] = nil
        matches = [:]
        resolve()
    }

    private func clearMessages(of app: String) {
        for source in sources where source.messagesClearOnFocus { messages[source.name]?[app] = nil }
        matches[app] = nil
    }

    private func clearOnFocus(_ id: CGWindowID) -> Bool {
        guard matches.values.contains(where: { $0[id] != nil }),
              let app = windowList().first(where: { $0.id == id })?.bundleID else { return false }
        let peers = Self.titles(of: windowList().filter { $0.bundleID == app })
        var cleared = false
        for source in sources where source.messagesClearOnFocus {
            guard let list = messages[source.name]?[app] else { continue }
            let kept = list.filter { Self.owner(of: $0, in: peers) != id }
            guard kept.count != list.count else { continue }
            messages[source.name]?[app] = kept.isEmpty ? nil : kept
            cleared = true
        }
        if cleared { matches[app] = nil }
        return cleared
    }

    private func resolve() {
        var next: [CGWindowID: (badge: Badge, source: String)] = [:]
        let all = enabled ? windowList() : []
        let ids = Set(all.map(\.id))
        if ids != known { matches = [:] }
        known = ids
        let waiting = Set(messages.values.flatMap(\.keys))
        if waiting.contains(where: { matches[$0] == nil }) {
            let relevant = all.filter { $0.bundleID.map(waiting.contains) == true }
            let byApp = Dictionary(grouping: relevant) { $0.bundleID ?? "" }
            for app in waiting where matches[app] == nil {
                matches[app] = match(app, in: Self.titles(of: byApp[app] ?? []))
            }
        }
        matches = matches.filter { waiting.contains($0.key) }
        var matched: Matches = [:]
        for perApp in matches.values { matched.merge(perApp) { first, _ in first } }
        for window in all {
            let app = window.bundleID.flatMap { apps[$0] }.flatMap(first)
            let own = windows[window.id].flatMap(first) ?? matched[window.id].map { (Badge.count($0.count), $0.source) }
            guard let badge = Badge.resolve(app: app?.badge, own: own?.badge) else { continue }
            next[window.id] = (badge, badge == own?.badge ? own?.source ?? "" : app?.source ?? "")
        }
        let changed = Set(next.keys).union(shown.keys).filter { next[$0]?.badge != shown[$0]?.badge }
        shown = next
        guard !changed.isEmpty else { return }
        let pairs = all.compactMap { window in window.bundleID.map { (window.id, $0) } }
        let bundles = Dictionary(pairs) { first, _ in first }
        for id in changed.sorted() {
            let change = Change(window: id, app: bundles[id], badge: next[id]?.badge, source: next[id]?.source)
            listeners.values.forEach { $0(change) }
            EventBus.shared.emit("window.notifications", [
                "window": .int(Int(id)), "app": change.app.map(JSON.string) ?? .null,
                "count": change.badge?.count.map(JSON.int) ?? .null, "dot": .bool(change.badge == .dot),
                "source": change.source.map(JSON.string) ?? .null
            ])
        }
    }

    private func first(_ badges: [String: Badge]) -> (badge: Badge, source: String)? {
        for source in sources {
            if let badge = badges[source.name] { return (badge, source.name) }
        }
        return badges.first.map { ($0.value, $0.key) }
    }

    private typealias Matches = [CGWindowID: (count: Int, source: String)]

    private func match(_ app: String, in titles: [(id: CGWindowID, title: String)]) -> Matches {
        var out: Matches = [:]
        guard !titles.isEmpty else { return out }
        for (source, perApp) in messages {
            for message in perApp[app] ?? [] {
                guard let owner = Self.owner(of: message, in: titles) else { continue }
                out[owner, default: (0, source)].count += 1
            }
        }
        return out
    }

    package static func titles(of windows: [Window]) -> [(id: CGWindowID, title: String)] {
        windows.compactMap { window in
            guard let title = window.title, !title.isEmpty else { return nil }
            return (window.id, title.lowercased())
        }
    }

    package static func owner(of message: NotificationMessage,
                              in titles: [(id: CGWindowID, title: String)]) -> CGWindowID? {
        let keys = [message.title, message.subtitle].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 2 }
        guard !keys.isEmpty else { return nil }
        var hit: CGWindowID?
        for window in titles where keys.contains(where: window.title.contains) {
            if hit != nil { return nil }
            hit = window.id
        }
        return hit
    }
}

extension Notifications {
    package func installBuiltIn() {
        let dock = DockBadgeSource(), database = NotificationDatabase()
        let banners = [BannerSource(reportsMessages: true), BannerSource(reportsMessages: false)]
        database.changed = { [weak dock] in dock?.pollSoon() }
        register(dock)
        register(database)
        for banner in banners {
            banner.changed = { [weak dock] in dock?.pollSoon() }
            register(banner)
        }
        var queued = false
        listen { _ in
            guard !queued else { return }
            queued = true
            DispatchQueue.main.async {
                queued = false
                WindowManager.shared.surface.tabsDidChange(instant: false)
            }
        }
    }
}
