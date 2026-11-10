import AppKit

package struct TilingRecovery: Codable, Equatable {
    package struct Identity: Codable, Hashable {
        package let id: CGWindowID
        package let pid: pid_t
        package let bundleID: String?
    }

    package struct MenuBar: Codable, Equatable {
        package let height: CGFloat
        package let visible: CGRect
    }

    package enum Placement: String, Codable { case tiled, floating }

    package struct Memo: Codable, Equatable {
        package var title = ""
        package var frame: CGRect?
        package var chosen: Placement?
        package var tabs: [Identity] = []
        package var activeTab = false
    }

    package struct Arrival {
        package let identity: Identity
        package let title: String
        package let frame: CGRect?
    }

    package static let departedLifetime: TimeInterval = 7 * 24 * 60 * 60

    package var order: [Identity] = []
    package var zoomed: [String: Identity] = [:]
    package var menuBars: [String: MenuBar] = [:]
    package var memos: [Identity: Memo] = [:]
    package var departed: [Identity: Date] = [:]

    private enum CodingKeys: String, CodingKey { case order, zoomed, menuBars, memos, departed }

    package init(order: [Identity] = [], zoomed: [String: Identity] = [:], menuBars: [String: MenuBar] = [:],
                 memos: [Identity: Memo] = [:], departed: [Identity: Date] = [:]) {
        self.order = order
        self.zoomed = zoomed
        self.menuBars = menuBars
        self.memos = memos
        self.departed = departed
    }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        order = try values.decodeIfPresent([Identity].self, forKey: .order) ?? []
        zoomed = try values.decodeIfPresent([String: Identity].self, forKey: .zoomed) ?? [:]
        menuBars = try values.decodeIfPresent([String: MenuBar].self, forKey: .menuBars) ?? [:]
        memos = try values.decodeIfPresent([Identity: Memo].self, forKey: .memos) ?? [:]
        departed = try values.decodeIfPresent([Identity: Date].self, forKey: .departed) ?? [:]
    }

    package var validated: Self {
        var seen = Set<Identity>(), live = Set<CGWindowID>()
        let entries = order.filter { entry in
            entry.id != 0 && entry.pid > 0 && seen.insert(entry).inserted
                && (departed[entry] != nil || live.insert(entry.id).inserted)
        }
        let kept = Set(entries)
        let bars = menuBars.filter { display, bar in
            !display.isEmpty && bar.height > 0 && bar.height <= 60
                && [bar.visible.minX, bar.visible.minY, bar.visible.width, bar.visible.height].allSatisfy(\.isFinite)
                && bar.visible.width > 0 && bar.visible.height > 0
        }
        return Self(order: entries, zoomed: zoomed.filter { !$0.key.isEmpty && kept.contains($0.value) },
                    menuBars: bars, memos: memos.filter { kept.contains($0.key) }.mapValues(\.checked),
                    departed: departed.filter { kept.contains($0.key) })
    }

    package func restoredOrder(_ current: [CGWindowID], arriving: Set<CGWindowID>, windows: [CGWindowID: Identity])
        -> [CGWindowID] {
        let saved = Set(order)
        let restoring = current.filter { arriving.contains($0) && windows[$0].map(saved.contains) == true }
        let ranks = ranks
        return Self.insert(restoring, into: current) { windows[$0].flatMap { ranks[$0] } }
    }

    package func restoredZooms(arriving: Set<CGWindowID>, windows: [CGWindowID: Identity],
                               workspaces: [CGWindowID: String], eligible: Set<CGWindowID>) -> [String: CGWindowID] {
        zoomed.compactMapValues { entry in
            arriving.contains(entry.id) && eligible.contains(entry.id) && windows[entry.id] == entry ? entry.id : nil
        }.filter { workspaces[$0.value] == $0.key }
    }

    package func capturing(order current: [CGWindowID], windows: [CGWindowID: Identity], zooms: [String: CGWindowID],
                           available: [CGWindowID: pid_t]?, menuBars: [String: MenuBar] = [:],
                           memos live: [Identity: Memo] = [:], departing: (Identity) -> Bool = { _ in false },
                           now: Date = Date()) -> Self {
        let present = Set(windows.values)
        func pending(_ entry: Identity) -> Bool {
            windows[entry.id] == nil
                && (available == nil || available?[entry.id] == entry.pid || available?[entry.id] == 0)
        }
        var gone = departed.filter { now.timeIntervalSince($0.value) < Self.departedLifetime }
        for entry in order where !present.contains(entry) && gone[entry] == nil && departed[entry] == nil
            && !pending(entry) && departing(entry) {
            gone[entry] = now
        }
        func kept(_ entry: Identity) -> Bool { !present.contains(entry) && (gone[entry] != nil || pending(entry)) }
        let waiting = order.filter(kept)
        let ranks = ranks
        let identities = Self.insert(waiting, into: current.compactMap { windows[$0] }) { ranks[$0] }
        var restored = zoomed.filter { kept($0.value) }
        for (workspace, id) in zooms { restored[workspace] = windows[id] }
        let notes = live.merging(self.memos.filter { kept($0.key) }) { current, _ in current }
        return Self(order: identities, zoomed: restored, menuBars: menuBars, memos: notes,
                    departed: gone.filter { kept($0.key) }).validated
    }

    package mutating func rebind(_ arrivals: [Arrival]) -> [Identity: Identity] {
        let known = Set(order)
        let fresh = arrivals.filter { !known.contains($0.identity) && $0.identity.bundleID != nil }
        let gone = order.filter { departed[$0] != nil && $0.bundleID != nil }
        guard !fresh.isEmpty, !gone.isEmpty else { return [:] }
        let saved = gone.map { entry in
            SavedWindow(bundleID: entry.bundleID ?? "", appName: "", title: memos[entry]?.title ?? "",
                        document: nil, display: "", frame: memos[entry]?.frame ?? .null, floating: false,
                        minimized: false, fullscreen: false, zoomed: false, focused: false, windowID: entry.id,
                        launchDate: nil)
        }
        let candidates = fresh.map { arrival in
            WindowCandidate(windowID: arrival.identity.id, bundleID: arrival.identity.bundleID ?? "",
                            title: arrival.title, document: nil, launchDate: nil, allowsGenericFallback: true,
                            newlyOpened: true, frame: arrival.frame)
        }
        let assigned = WindowMatch.assign(saved, candidates: candidates)
        let arriving = Dictionary(fresh.map { ($0.identity.id, $0.identity) }, uniquingKeysWith: { first, _ in first })
        var pairs: [Identity: Identity] = [:]
        for (entry, window) in zip(gone, saved) {
            if let id = assigned[window.id], let identity = arriving[id] { pairs[entry] = identity }
        }
        guard !pairs.isEmpty else { return [:] }
        func swap(_ entry: Identity) -> Identity { pairs[entry] ?? entry }
        order = order.map(swap)
        zoomed = zoomed.mapValues(swap)
        memos = Dictionary(memos.map { entry, memo in
            var memo = memo
            memo.tabs = memo.tabs.map(swap)
            return (swap(entry), memo)
        }, uniquingKeysWith: { first, _ in first })
        departed = departed.filter { pairs[$0.key] == nil }
        return pairs
    }

    package mutating func forget(_ identity: Identity) {
        order.removeAll { $0 == identity }
        zoomed = zoomed.filter { $0.value != identity }
        memos[identity] = nil
        departed[identity] = nil
    }

    private var ranks: [Identity: Int] {
        Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    private static func insert<T: Hashable>(_ restored: [T], into current: [T], rank: (T) -> Int?) -> [T] {
        let restoring = Set(restored)
        var result = current.filter { !restoring.contains($0) }
        for item in restored.sorted(by: { (rank($0) ?? .max) < (rank($1) ?? .max) }) {
            guard let value = rank(item) else { result.append(item); continue }
            let next = result.firstIndex { rank($0).map { $0 > value } == true }
            let previous = result.lastIndex { rank($0).map { $0 < value } == true }
            result.insert(item, at: next ?? previous.map { $0 + 1 } ?? result.endIndex)
        }
        return result
    }
}

private extension TilingRecovery.Memo {
    var checked: Self {
        var memo = self
        if let frame, ![frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) || frame.isEmpty {
            memo.frame = nil
        }
        return memo
    }
}
