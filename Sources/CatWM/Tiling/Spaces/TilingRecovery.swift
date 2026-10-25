import AppKit

struct TilingRecovery: Codable, Equatable {
    struct Identity: Codable, Equatable {
        let id: CGWindowID
        let pid: pid_t
        let bundleID: String?
    }

    struct MenuBar: Codable, Equatable {
        let height: CGFloat
        let visible: CGRect
    }

    var order: [Identity] = []
    var zoomed: [String: Identity] = [:]
    var menuBars: [String: MenuBar] = [:]

    private enum CodingKeys: String, CodingKey { case order, zoomed, menuBars }

    init(order: [Identity] = [], zoomed: [String: Identity] = [:], menuBars: [String: MenuBar] = [:]) {
        self.order = order
        self.zoomed = zoomed
        self.menuBars = menuBars
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        order = try values.decodeIfPresent([Identity].self, forKey: .order) ?? []
        zoomed = try values.decodeIfPresent([String: Identity].self, forKey: .zoomed) ?? [:]
        menuBars = try values.decodeIfPresent([String: MenuBar].self, forKey: .menuBars) ?? [:]
    }

    var validated: Self {
        var seen = Set<CGWindowID>()
        let entries = order.filter { $0.id != 0 && $0.pid > 0 && seen.insert($0.id).inserted }
        let identities = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let bars = menuBars.filter { display, bar in
            !display.isEmpty && bar.height > 0 && bar.height <= 60
                && [bar.visible.minX, bar.visible.minY, bar.visible.width, bar.visible.height].allSatisfy(\.isFinite)
                && bar.visible.width > 0 && bar.visible.height > 0
        }
        return Self(order: entries, zoomed: zoomed.filter { !$0.key.isEmpty && identities[$0.value.id] == $0.value },
                    menuBars: bars)
    }

    func restoredOrder(_ current: [CGWindowID], arriving: Set<CGWindowID>, windows: [CGWindowID: Identity])
        -> [CGWindowID] {
        let saved = Dictionary(order.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restoring = current.filter { arriving.contains($0) && saved[$0] != nil && saved[$0] == windows[$0] }
        return Self.insert(restoring, into: current, ranks: ranks(windows: windows))
    }

    func restoredZooms(arriving: Set<CGWindowID>, windows: [CGWindowID: Identity],
                       workspaces: [CGWindowID: String], eligible: Set<CGWindowID>) -> [String: CGWindowID] {
        zoomed.compactMapValues { entry in
            arriving.contains(entry.id) && eligible.contains(entry.id) && windows[entry.id] == entry ? entry.id : nil
        }.filter { workspaces[$0.value] == $0.key }
    }

    func capturing(order current: [CGWindowID], windows: [CGWindowID: Identity], zooms: [String: CGWindowID],
                   available: [CGWindowID: pid_t]?, menuBars: [String: MenuBar] = [:]) -> Self {
        func pending(_ entry: Identity) -> Bool {
            windows[entry.id] == nil
                && (available == nil || available?[entry.id] == entry.pid || available?[entry.id] == 0)
        }
        let waiting = order.filter(pending)
        let combined = windows.merging(Dictionary(waiting.map { ($0.id, $0) },
                                                   uniquingKeysWith: { first, _ in first })) { current, _ in current }
        let ids = Self.insert(waiting.map(\.id), into: current, ranks: ranks(windows: windows))
        var restored = zoomed.filter { pending($0.value) }
        for (workspace, id) in zooms { restored[workspace] = windows[id] }
        return Self(order: ids.compactMap { combined[$0] }, zoomed: restored, menuBars: menuBars).validated
    }

    mutating func forget(_ id: CGWindowID) {
        order.removeAll { $0.id == id }
        zoomed = zoomed.filter { $0.value.id != id }
    }

    private func ranks(windows: [CGWindowID: Identity]) -> [CGWindowID: Int] {
        Dictionary(order.enumerated().filter { entry in
            windows[entry.element.id].map { $0 == entry.element } ?? true
        }
            .map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    private static func insert(_ restored: [CGWindowID], into current: [CGWindowID], ranks: [CGWindowID: Int])
        -> [CGWindowID] {
        let restoring = Set(restored)
        var result = current.filter { !restoring.contains($0) }
        for id in restoring.sorted(by: { (ranks[$0] ?? .max) < (ranks[$1] ?? .max) }) {
            guard let rank = ranks[id] else { result.append(id); continue }
            let next = result.firstIndex { ranks[$0].map { $0 > rank } == true }
            let previous = result.lastIndex { ranks[$0].map { $0 < rank } == true }
            result.insert(id, at: next ?? previous.map { $0 + 1 } ?? result.endIndex)
        }
        return result
    }
}
