import AppKit

struct EventSpec {
    let name: String
    let summary: String
    let data: [Field]
}

struct StateSnapshot: Equatable {
    struct Entry: Equatable {
        var app: String?
        var title: String?
    }

    var focused: CGWindowID?
    var windows: [CGWindowID: Entry] = [:]
    var workspaces: [String: String] = [:]
    var layouts: [String: String] = [:]
    var tiling = true
    var mode = ""
}

final class EventBus {
    static let shared = EventBus()

    static let specs: [EventSpec] = [
        EventSpec(name: "focus.changed", summary: "The focused window changed", data: [
            Field(name: "window", type: "int?", summary: "Window ID, or null when no window has focus"),
            Field(name: "app", type: "string?", summary: "Bundle ID"),
            Field(name: "title", type: "string?", summary: "Window title")
        ]),
        EventSpec(name: "window.added", summary: "CatWM found a new window", data: [
            Field(name: "window", type: "int", summary: "Window ID"),
            Field(name: "app", type: "string?", summary: "Bundle ID"),
            Field(name: "title", type: "string?", summary: "Window title")
        ]),
        EventSpec(name: "window.removed", summary: "A window is gone", data: [
            Field(name: "window", type: "int", summary: "Window ID"),
            Field(name: "app", type: "string?", summary: "Bundle ID")
        ]),
        EventSpec(name: "workspace.changed", summary: "A display shows another workspace", data: [
            Field(name: "screen", type: "string", summary: "Display ID"),
            Field(name: "workspace", type: "string", summary: "Workspace name")
        ]),
        EventSpec(name: "layout.changed", summary: "A display uses another layout", data: [
            Field(name: "screen", type: "string", summary: "Display ID"),
            Field(name: "layout", type: "string", summary: "Layout name")
        ]),
        EventSpec(name: "tiling.changed", summary: "Tiling went on or off", data: [
            Field(name: "enabled", type: "bool", summary: "Tiling is on")
        ]),
        EventSpec(name: "mode.changed", summary: "The key mode changed", data: [
            Field(name: "mode", type: "string", summary: "Key mode, empty for none")
        ]),
        EventSpec(name: "window.notifications", summary: "The unread badge of a window changed", data: [
            Field(name: "window", type: "int", summary: "Window ID"),
            Field(name: "app", type: "string?", summary: "Bundle ID"),
            Field(name: "count", type: "int?", summary: "Unread count, or null for a dot or no badge"),
            Field(name: "dot", type: "bool", summary: "The app shows unread items with no number"),
            Field(name: "source", type: "string?", summary: "dock, banner or database, or null")
        ]),
        EventSpec(name: "config.reloaded", summary: "CatWM applied the config again", data: [
            Field(name: "errors", type: "object[]",
                  summary: "Problems in the config: file, line, phase and message. "
                    + "A failed save keeps the last good config")
        ])
    ]

    static let allNames = specs.map(\.name)

    static func names(_ raw: JSON?) throws -> [String] {
        let requested = raw?.array?.compactMap(\.string) ?? []
        if let unknown = requested.first(where: { !allNames.contains($0) }) {
            throw ControlError.invalid("Unknown event `\(unknown)`. Events: \(allNames.joined(separator: ", "))")
        }
        return requested.isEmpty ? allNames : requested
    }

    private var subscriptions: [ObjectIdentifier: (client: ControlConnection, events: Set<String>)] = [:]
    private var last: StateSnapshot?

    var hasSubscribers: Bool { !subscriptions.isEmpty }

    func subscribe(_ client: ControlConnection, to events: [String]) -> [String] {
        let wasIdle = subscriptions.isEmpty
        let key = ObjectIdentifier(client)
        let merged = (subscriptions[key]?.events ?? []).union(events)
        subscriptions[key] = (client, merged)
        if wasIdle { last = WindowManager.shared.snapshot() }
        return Self.allNames.filter(merged.contains)
    }

    func unsubscribe(_ client: ControlConnection, from events: [String]) -> [String] {
        let key = ObjectIdentifier(client)
        guard var entry = subscriptions[key] else { return [] }
        entry.events.subtract(events)
        subscriptions[key] = entry.events.isEmpty ? nil : entry
        if subscriptions.isEmpty { last = nil }
        return Self.allNames.filter(entry.events.contains)
    }

    func remove(_ client: ControlConnection) {
        subscriptions[ObjectIdentifier(client)] = nil
        if subscriptions.isEmpty { last = nil }
    }

    func emit(_ name: String, _ data: JSON) {
        guard hasSubscribers else { return }
        let line = JSON.object(["event": .string(name), "data": data]).encoded() + Data("\n".utf8)
        for entry in subscriptions.values where entry.events.contains(name) { entry.client.send(line) }
    }

    func stateChanged() {
        guard hasSubscribers, let previous = last else { return }
        let current = WindowManager.shared.snapshot()
        guard current != previous else { return }
        last = current
        for change in Self.changes(from: previous, to: current) { emit(change.0, change.1) }
    }

    static func changes(from old: StateSnapshot, to new: StateSnapshot) -> [(String, JSON)] {
        var out: [(String, JSON)] = []
        func info(_ id: CGWindowID, _ entry: StateSnapshot.Entry) -> [String: JSON] {
            ["window": .int(Int(id)), "app": entry.app.map(JSON.string) ?? .null,
             "title": entry.title.map(JSON.string) ?? .null]
        }
        for id in new.windows.keys.sorted() where old.windows[id] == nil {
            out.append(("window.added", .object(info(id, new.windows[id] ?? .init()))))
        }
        for id in old.windows.keys.sorted() where new.windows[id] == nil {
            var data = info(id, old.windows[id] ?? .init())
            data["title"] = nil
            out.append(("window.removed", .object(data)))
        }
        if old.focused != new.focused {
            let entry = new.focused.flatMap { new.windows[$0] }
            out.append(("focus.changed", .object([
                "window": new.focused.map { .int(Int($0)) } ?? .null,
                "app": entry?.app.map(JSON.string) ?? .null, "title": entry?.title.map(JSON.string) ?? .null
            ])))
        }
        for screen in new.workspaces.keys.sorted() where old.workspaces[screen] != new.workspaces[screen] {
            out.append(("workspace.changed",
                        ["screen": .string(screen), "workspace": .string(new.workspaces[screen] ?? "")]))
        }
        for screen in new.layouts.keys.sorted() where old.layouts[screen] != new.layouts[screen] {
            out.append(("layout.changed", ["screen": .string(screen), "layout": .string(new.layouts[screen] ?? "")]))
        }
        if old.tiling != new.tiling { out.append(("tiling.changed", ["enabled": .bool(new.tiling)])) }
        if old.mode != new.mode { out.append(("mode.changed", ["mode": .string(new.mode)])) }
        return out
    }
}

extension WindowManager {
    func snapshot() -> StateSnapshot {
        var snapshot = StateSnapshot()
        snapshot.focused = reportedFocusedWindow()?.id
        snapshot.windows = windows.mapValues { StateSnapshot.Entry(app: $0.bundleID, title: $0.title) }
        snapshot.tiling = tilingEnabled
        snapshot.mode = Hotkeys.shared.submap
        for screen in backend.screens() {
            snapshot.workspaces[screen.uuid] = shown[screen.uuid] ?? ""
            let layout = states[workspaceKey(for: screen)]?.layout ?? config.layouts.first
            snapshot.layouts[screen.uuid] = layout?.rawValue
        }
        return snapshot
    }

    func notifyChange() {
        onChange?()
        Notifications.shared.stateChanged(focused: reportedFocusedWindow()?.id)
        EventBus.shared.stateChanged()
    }
}
