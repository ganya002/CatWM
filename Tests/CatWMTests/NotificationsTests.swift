import AppKit
@testable import CatWM
import SQLite3
import Testing

@Suite struct NotificationsTests {
    private final class Fake: NotificationSource {
        let name: String
        var messagesClearOnFocus = false
        private(set) var sink: NotificationSink?
        init(_ name: String) { self.name = name }
        func start(_ sink: NotificationSink) { self.sink = sink }
        func stop() { sink = nil }
    }

    private func window(_ id: CGWindowID, _ app: String?, _ title: String?) -> Window {
        let window = Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: app)
        window.title = title
        return window
    }

    @Test func dockCountGoesToEachWindowUnlessAWindowKnowsLess() {
        #expect(Badge.resolve(app: .count(5), own: nil) == .count(5))
        #expect(Badge.resolve(app: .count(5), own: .count(2)) == .count(2))
        #expect(Badge.resolve(app: .count(5), own: .count(9)) == .count(5))
        #expect(Badge.resolve(app: nil, own: .count(3)) == .count(3))
        #expect(Badge.resolve(app: .dot, own: nil) == .dot)
        #expect(Badge.resolve(app: .dot, own: .count(1)) == .count(1))
        #expect(Badge.resolve(app: nil, own: nil) == nil)
    }

    @Test func badgeReadsDockLabels() {
        #expect(Badge(label: "174") == .count(174))
        #expect(Badge(label: "!") == .dot)
        #expect(Badge(label: "") == nil)
        #expect(Badge(label: nil) == nil)
        #expect(Badge.count(120).text == "99+")
    }

    @Test @MainActor func dockUpdateRechecksMessagesWhenWindowsChange() {
        var windows = [window(1, "com.slack", "general - Slack")]
        let registry = Notifications(windowList: { windows })
        let dock = Fake("dock"), banner = Fake("banner")
        registry.register(dock)
        registry.register(banner)
        registry.setEnabled(true)
        dock.sink?.report(app: "com.slack", .count(4), from: dock.name)
        banner.sink?.add(NotificationMessage(app: "com.slack", title: "general"), from: banner.name)
        #expect(registry.badge(for: 1) == .count(1))

        windows.append(window(2, "com.slack", "general - Slack"))
        dock.sink?.report(app: "com.slack", .count(5), from: dock.name)
        registry.stateChanged(focused: nil)
        #expect(registry.badge(for: 1) == .count(5))
        #expect(registry.badge(for: 2) == .count(5))

        windows.removeFirst()
        dock.sink?.report(app: "com.slack", .count(4), from: dock.name)
        registry.stateChanged(focused: nil)
        #expect(registry.badge(for: 1) == nil)
        #expect(registry.badge(for: 2) == .count(1))
    }

    @Test @MainActor func listenersGetEachChangeAndMessagesFindTheirWindow() {
        var windows = [window(1, "com.slack", "general - Acme - Slack"),
                       window(2, "com.slack", "random - Acme - Slack"), window(3, "com.other", "Other")]
        let registry = Notifications(windowList: { windows })
        let dock = Fake("dock"), banner = Fake("banner")
        banner.messagesClearOnFocus = true
        registry.register(dock)
        registry.register(banner)
        var changes: [Notifications.Change] = []
        let token = registry.listen { changes.append($0) }
        registry.setEnabled(true)

        dock.sink?.report(app: "com.slack", .count(4), from: dock.name)
        #expect(registry.badge(for: 1) == .count(4))
        #expect(registry.badge(for: 2) == .count(4))
        #expect(registry.badge(for: 3) == nil)
        #expect(changes.map(\.window) == [1, 2])

        banner.sink?.add(NotificationMessage(app: "com.slack", title: "random"), from: banner.name)
        #expect(registry.badge(for: 2) == .count(1))
        #expect(registry.badge(for: 1) == .count(4))

        registry.stateChanged(focused: 2)
        #expect(registry.badge(for: 2) == .count(4))

        registry.stopListening(token)
        let seen = changes.count
        dock.sink?.report(app: "com.slack", nil, from: dock.name)
        #expect(registry.badge(for: 1) == nil)
        #expect(changes.count == seen)

        dock.sink?.report(app: "com.slack", .count(1), from: dock.name)
        windows.append(window(4, "com.slack", "new - Acme - Slack"))
        #expect(registry.badge(for: 4) == nil)
        registry.stateChanged(focused: 2)
        #expect(registry.badge(for: 4) == .count(1))
        registry.setEnabled(false)
        #expect(registry.badge(for: 1) == nil)
        #expect(dock.sink == nil)
    }
}

@Suite struct NotificationDatabaseCacheTests {
    private func plist(_ title: String) -> Data {
        let root: [String: Any] = ["app": "x", "req": ["titl": title, "body": "hi"]]
        return (try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)) ?? Data()
    }

    private func run(_ database: OpaquePointer?, _ sql: String) {
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func insert(_ database: OpaquePointer?, _ id: Int, app: Int, _ title: String) {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, "INSERT INTO record (rec_id, app_id, data) VALUES (?, ?, ?)", -1, &statement, nil)
        sqlite3_bind_int64(statement, 1, Int64(id))
        sqlite3_bind_int64(statement, 2, Int64(app))
        let data = plist(title)
        _ = data.withUnsafeBytes { bytes in
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), transient)
        }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    @Test func readsNewRowsAndSeesDeletedOnes() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("notif-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var database: OpaquePointer?
        sqlite3_open(path, &database)
        defer { sqlite3_close(database) }
        run(database, "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT)")
        run(database, "CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB)")
        run(database, "INSERT INTO app VALUES (1, 'com.slack'), (2, 'com.hnc.Discord')")
        insert(database, 1, app: 1, "general")
        insert(database, 2, app: 2, "Marius")

        let cache = NotificationDatabase.Cache()
        let first = try #require(cache.load(from: path))
        #expect(first["com.slack"]?.map(\.title) == ["general"])
        #expect(first["com.hnc.Discord"]?.map(\.title) == ["Marius"])
        #expect(cache.load(from: path) == nil)

        insert(database, 3, app: 1, "random")
        insert(database, 4, app: 9, "no app")
        let second = try #require(cache.load(from: path))
        #expect(second["com.slack"]?.map(\.title) == ["general", "random"])
        #expect(second["com.hnc.Discord"] == nil)
        #expect(cache.load(from: path) == nil)

        run(database, "DELETE FROM record WHERE rec_id = 1")
        let third = try #require(cache.load(from: path))
        #expect(third["com.slack"]?.map(\.title) == ["random"])
    }
}
