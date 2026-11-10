import AppKit
import SQLite3
package final class NotificationDatabase: NotificationSource {
    package let name = "database"
    private weak var sink: NotificationSink?
    private let queue = DispatchQueue(label: "catwm.notifications.database", qos: .utility)
    private var watcher: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let cache = Cache()

    package static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2")
    package static let path = folder.appendingPathComponent("db").path
    package static let walPath = folder.appendingPathComponent("db-wal").path
    package var changed: () -> Void = {}

    package static var isReadable: Bool {
        let handle = open(path, O_RDONLY)
        guard handle >= 0 else { return false }
        close(handle)
        return true
    }

    package var isAvailable: Bool { Self.isReadable }

    package func start(_ sink: NotificationSink) {
        self.sink = sink
        watch()
        read()
    }

    package func stop() {
        sink = nil
        pending?.cancel()
        watcher?.cancel()
        watcher = nil
        queue.async { [cache] in cache.reset() }
    }

    private func watch() {
        let handle = open(Self.walPath, O_EVTONLY)
        guard handle >= 0 else { return rewatch(after: 5) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle,
                                                               eventMask: [.write, .extend, .delete, .rename],
                                                               queue: queue)
        source.setEventHandler { [weak self, weak source] in
            let moved = source.map { !$0.data.isDisjoint(with: [.delete, .rename]) } ?? false
            DispatchQueue.main.async {
                guard let self, self.sink != nil else { return }
                if moved {
                    self.watcher?.cancel()
                    self.watcher = nil
                    self.rewatch(after: 1)
                } else {
                    self.schedule()
                }
            }
        }
        source.setCancelHandler { close(handle) }
        source.resume()
        watcher = source
    }

    private func rewatch(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sink != nil, self.watcher == nil else { return }
            self.watch()
            self.read()
        }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.read() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func read() {
        queue.async { [weak self] in
            guard let self, let changed = self.cache.load(from: Self.path) else { return }
            DispatchQueue.main.async {
                guard let sink = self.sink else { return }
                for (app, list) in changed { sink.report(messages: list, for: app, from: self.name) }
                self.changed()
            }
        }
    }

    package final class Cache {
        private var rows: [Int64: NotificationMessage?] = [:]
        private var lists: [String: [NotificationMessage]] = [:]
        private var last: Int64 = 0
        private var touched: Set<String> = []

        package func reset() {
            rows = [:]
            lists = [:]
            last = 0
        }

        package func load(from path: String) -> [String: [NotificationMessage]]? {
            var database: OpaquePointer?
            guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
                sqlite3_close(database)
                return nil
            }
            defer { sqlite3_close(database) }
            sqlite3_busy_timeout(database, 200)
            guard let (count, newest) = Self.size(of: database) else { return nil }
            if count == rows.count, newest == last { return nil }
            touched = []
            if newest < last || !add(from: database) || rows.count != count {
                let before = Set(lists.keys)
                reset()
                guard add(from: database) else { return nil }
                touched.formUnion(before)
            }
            return Dictionary(uniqueKeysWithValues: touched.map { app in
                (app, Array((lists[app] ?? []).suffix(Notifications.messageLimit)))
            })
        }

        private static func size(of database: OpaquePointer) -> (Int, Int64)? {
            var statement: OpaquePointer?
            let sql = "SELECT count(*), coalesce(max(rec_id), 0) FROM record"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return (Int(sqlite3_column_int64(statement, 0)), sqlite3_column_int64(statement, 1))
        }

        private func add(from database: OpaquePointer) -> Bool {
            let sql = "SELECT record.rec_id, app.identifier, record.data FROM record "
                + "LEFT JOIN app ON app.app_id = record.app_id WHERE record.rec_id > ? ORDER BY record.rec_id"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, last)
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                last = max(last, id)
                guard let app = sqlite3_column_text(statement, 1), let bytes = sqlite3_column_blob(statement, 2) else {
                    rows[id] = .some(nil)
                    continue
                }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
                let message = NotificationDatabase.message(app: String(cString: app), plist: data)
                rows[id] = message
                lists[message.app, default: []].append(message)
                touched.insert(message.app)
            }
            return true
        }
    }

    package static func message(app: String, plist: Data) -> NotificationMessage {
        let root = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
        let request = root?["req"] as? [String: Any] ?? [:]
        return NotificationMessage(app: app, title: request["titl"] as? String ?? "",
                                   subtitle: request["subt"] as? String ?? "", body: request["body"] as? String ?? "")
    }
}
