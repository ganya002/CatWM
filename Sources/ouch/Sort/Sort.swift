import AppKit

// Sort Windows, the data side: what the window manager hands the panel (`SortDisplay`), the plan the
// panel edits (`SortPlan`) and the groupings that fill it. Nothing here moves a window; the panel hands
// edited plans to `WindowManager.liveSort`.

/// How the panel groups windows when it opens, and when a grouping is picked.
enum SortStrategy: String, CaseIterable {
    case task, app, focus, none

    var title: String {
        switch self {
        case .task: "By task"
        case .app: "By app"
        case .focus: "Focus"
        case .none: "Start empty"
        }
    }
}

/// One window the panel can place.
struct SortItem: Identifiable {
    let id: CGWindowID
    let title: String
    let app: String
    let bundleID: String?
    let icon: NSImage?
    /// 0 is the window used most recently.
    let recency: Int
}

/// A workspace as it is now.
struct SortWorkspace {
    let name: String
    let label: String
    let layout: Layout
    let ratio: CGFloat
    let mainCount: Int
    /// Tiling order, main window first.
    let ids: [CGWindowID]
}

/// One display and everything on it, for the panel.
struct SortDisplay: Identifiable {
    let id: String
    let name: String
    /// A short name for the picker: "Built-in", "Studio".
    let short: String
    let isLaptop: Bool
    /// Width over height, for the little screen glyph.
    let aspect: CGFloat
    let screen: NSScreen
    /// Tiled windows on this display, in tiling order.
    let items: [SortItem]
    /// Workspaces that hold windows here, plus the one the display shows.
    let workspaces: [SortWorkspace]
    /// The workspace the display is showing.
    let active: String?
    /// Workspace names in use on other displays.
    let taken: Set<String>

    var isSorted: Bool { workspaces.filter { !$0.ids.isEmpty }.count > 1 }
}

// MARK: - Plan

/// A workspace that was dropped on Close: its windows are marked, and it can be brought back whole.
struct SortClosedLane: Identifiable {
    let id = UUID()
    var ws: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}

struct SortLane: Identifiable {
    let id = UUID()
    /// The workspace this lane becomes.
    var ws: String
    /// What the user called it; may be empty.
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}

/// What one display will look like after Sort: lanes left to right, each one a workspace with its real
/// name (number), and the windows that will be closed.
struct SortPlan {
    static let maxLanes = 10

    let display: String
    var items: [CGWindowID: SortItem]
    var lanes: [SortLane]
    /// Every window marked to close, closed workspaces' windows included.
    var close: [CGWindowID] = []
    var closedLanes: [SortClosedLane] = []
    /// Where a window sat when it was marked, so it can go back: its workspace and place in it.
    var origin: [CGWindowID: (ws: String, at: Int)] = [:]
    /// The grouping last picked; nil while the display shows its current workspaces.
    var strategy: SortStrategy?
    /// The duplicates button was used: regrouping keeps them in Close.
    var duplicatesClosed = false
    /// Edited since the panel opened (or a window arrived from or left for another display).
    var touched = false
    /// Edited since it was last applied to the real windows.
    var pending = false
    let existing: [String]
    /// Workspaces this plan has applied, so the ones it lets go of later are cleaned up too.
    var claimed: Set<String> = []
    let taken: Set<String>
    let active: String?
    /// Split ratio and main count each existing workspace tiles with, for the thumbnails.
    var geometry: [String: (ratio: CGFloat, mainCount: Int)] = [:]

    // MARK: Building

    /// The display as it is now, one lane per workspace.
    static func current(of d: SortDisplay) -> SortPlan {
        var lanes = d.workspaces.map { SortLane(ws: $0.name, name: $0.label, layout: $0.layout, ids: $0.ids) }
        if lanes.isEmpty { lanes = [SortLane(ws: "1", name: "", layout: .tall, ids: [])] }
        var plan = SortPlan(display: d.id, items: Dictionary(d.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                            lanes: lanes, strategy: nil,
                            existing: d.workspaces.map(\.name), taken: d.taken, active: d.active)
        for w in d.workspaces { plan.geometry[w.name] = (w.ratio, w.mainCount) }
        return plan
    }

    /// The display grouped by `strategy`. `other` is every workspace name another open plan uses.
    static func grouped(_ d: SortDisplay, by strategy: SortStrategy, layouts: [Layout], avoiding other: Set<String>) -> SortPlan {
        var plan = current(of: d)
        plan.sort(by: strategy, layouts: layouts, avoiding: other)
        return plan
    }

    /// Workspaces sort numerically first ("2" before "10"), then by name.
    static func order(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    /// Names a new lane could take, best first: the display's own, then the first free numbers. A name
    /// is free when no lane here, no other display and no other open plan uses it.
    func available(avoiding other: Set<String>) -> [String] {
        let used = Set(lanes.map(\.ws))
        var out: [String] = []
        for n in existing + (1...10).map(String.init) where !out.contains(n) && !used.contains(n) && !taken.contains(n) && !other.contains(n) {
            out.append(n)
        }
        return out
    }

    func canAdd(avoiding other: Set<String>) -> Bool { lanes.count < Self.maxLanes && !available(avoiding: other).isEmpty }

    /// The lane for the workspace the display is showing, else the first.
    var activeLane: Int { lanes.firstIndex { $0.ws == active } ?? 0 }

    /// What a lane is called: its name, else "Workspace N".
    func title(of lane: Int) -> String {
        let n = lanes[lane].name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Workspace \(lanes[lane].ws)" : n
    }

    static func layout(forCount n: Int, in layouts: [Layout]) -> Layout {
        let want: Layout = n <= 1 ? .fullscreen : n == 2 ? .column : n == 3 ? .tall : n == 4 ? .bsp : .tall
        return layouts.contains(want) ? want : layouts.first ?? .tall
    }

    /// Regroups every window in the plan. Duplicates stay in Close once the duplicates button was used.
    mutating func sort(by s: SortStrategy, layouts: [Layout], avoiding other: Set<String>) {
        strategy = s
        let dupes = duplicatesClosed ? Set(duplicates) : []
        let live = items.values.filter { !dupes.contains($0.id) }.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }
        var groups: [(name: String, items: [SortItem], layout: Layout?)]
        switch s {
        case .task:
            groups = SortCategory.all.map { c in (c.rawValue, live.filter { SortCategory.of($0.bundleID) == c }, nil) }
        case .app:
            var count: [String: Int] = [:]
            for i in live { count[i.app, default: 0] += 1 }
            // Busiest first; ties go to the app used most recently.
            let ranked = count.keys.sorted { a, b in
                count[a]! != count[b]! ? count[a]! > count[b]!
                    : (live.first { $0.app == a }?.recency ?? 0) < (live.first { $0.app == b }?.recency ?? 0)
            }
            let own = Array(ranked.prefix(4))
            groups = own.map { a in (a, live.filter { $0.app == a }, nil) }
            let rest = live.filter { !own.contains($0.app) }
            if !rest.isEmpty { groups.append(("Everything else", rest, nil)) }
        case .focus:
            groups = [("Now", Array(live.prefix(3)), nil), ("Later", Array(live.dropFirst(3)), .fullscreen)]
        case .none:
            groups = [("", live, nil)]
        }
        groups = groups.filter { !$0.items.isEmpty }
        if groups.isEmpty { groups = [("", [], nil)] }
        lanes = []
        let pool = available(avoiding: other)
        let cap = max(1, min(Self.maxLanes, pool.count))
        while groups.count > cap {
            let last = groups.removeLast()
            groups[groups.count - 1].items += last.items
        }
        let names = Array(pool.prefix(groups.count)).sorted(by: Self.order)
        lanes = groups.enumerated().map { i, g in
            SortLane(ws: i < names.count ? names[i] : existing.first ?? "1", name: g.name,
                     layout: Self.fit(g.layout, g.items.count, layouts), ids: g.items.map(\.id))
        }
        closedLanes = []
        origin = [:]
        close = items.values.filter { dupes.contains($0.id) }.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }.map(\.id)
    }

    private static func fit(_ forced: Layout?, _ n: Int, _ layouts: [Layout]) -> Layout {
        if let forced { return layouts.contains(forced) ? forced : layouts.first ?? .tall }
        return layout(forCount: n, in: layouts)
    }

    // MARK: Duplicates

    /// Windows that show the same title in the same app as a more recently used one.
    var duplicates: [CGWindowID] {
        var groups: [String: [SortItem]] = [:]
        for i in items.values where !i.title.isEmpty && i.title != "Untitled" { groups["\(i.bundleID ?? i.app)\n\(i.title)", default: []].append(i) }
        return groups.values.flatMap { g in g.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }.dropFirst().map(\.id) }.sorted()
    }

    /// The footer's one-shot button for duplicates not yet in Close, "Close 2 duplicate Finder windows";
    /// nil when there is nothing to offer.
    var duplicateText: String? {
        let d = duplicates.filter { !close.contains($0) }
        guard !d.isEmpty else { return nil }
        let apps = Set(d.compactMap { items[$0]?.app })
        return "Close \(d.count) duplicate \(apps.count == 1 ? apps.first! + " " : "")window\(d.count == 1 ? "" : "s")"
    }

    mutating func closeDuplicates() {
        duplicatesClosed = true
        duplicates.forEach { markClosing($0) }
    }

    // MARK: Editing

    func lane(of id: CGWindowID) -> Int? { lanes.firstIndex { $0.ids.contains(id) } }
    func isClosing(_ id: CGWindowID) -> Bool { close.contains(id) }
    var allIDs: [CGWindowID] { lanes.flatMap(\.ids) + close }

    mutating func detach(_ id: CGWindowID) {
        for i in lanes.indices { lanes[i].ids.removeAll { $0 == id } }
        close.removeAll { $0 == id }
        origin[id] = nil
        for i in closedLanes.indices { closedLanes[i].ids.removeAll { $0 == id } }
        closedLanes.removeAll { $0.ids.isEmpty }
    }

    /// Puts a window in a lane, at the end unless `at` says where.
    mutating func place(_ id: CGWindowID, inLane i: Int, at index: Int? = nil) {
        guard lanes.indices.contains(i) else { return }
        detach(id)
        let at = min(index ?? lanes[i].ids.count, lanes[i].ids.count)
        lanes[i].ids.insert(id, at: at)
    }

    /// Puts a window in Close, remembering where it was so it can go back there.
    mutating func markClosing(_ id: CGWindowID) {
        guard !isClosing(id) else { return }
        let from = lane(of: id).flatMap { l in lanes[l].ids.firstIndex(of: id).map { (lanes[l].ws, $0) } }
        detach(id)
        close.append(id)
        if let from { origin[id] = from }
    }

    /// A new lane with `layout`, for workspace `named` (else the best free one), in numeric order; its index.
    @discardableResult
    mutating func addLane(layout: Layout, named: String? = nil, avoiding other: Set<String>) -> Int? {
        let free = available(avoiding: other)
        guard lanes.count < Self.maxLanes else { return nil }
        let name: String
        if let named {
            guard free.contains(named) else { return nil }
            name = named
        } else if let first = free.first {
            name = first
        } else {
            return nil
        }
        let at = lanes.firstIndex { Self.order(name, $0.ws) } ?? lanes.count
        lanes.insert(SortLane(ws: name, name: "", layout: layout, ids: []), at: at)
        return at
    }

    /// Drops a workspace on Close: the column goes and its windows are marked, as a group that can come back.
    /// Returns how many windows were marked.
    mutating func closeLane(at i: Int) -> Int? {
        guard lanes.count > 1, lanes.indices.contains(i) else { return nil }
        let lane = lanes.remove(at: i)
        guard !lane.ids.isEmpty else { return 0 }
        closedLanes.append(SortClosedLane(ws: lane.ws, name: lane.name, layout: lane.layout, ids: lane.ids))
        close += lane.ids
        return lane.ids.count
    }

    /// Brings a closed window back to the workspace it came from, at its old place; the whole workspace if
    /// that one is closed too; the shown workspace if it was removed.
    mutating func restore(_ id: CGWindowID, avoiding other: Set<String>) {
        guard isClosing(id) else { return }
        if let g = closedLanes.first(where: { $0.ids.contains(id) }) { return reopen(g.id, avoiding: other) }
        if let o = origin[id], let l = lanes.firstIndex(where: { $0.ws == o.ws }) {
            place(id, inLane: l, at: o.at)
        } else {
            place(id, inLane: activeLane)
        }
    }

    /// Brings a closed workspace back with its windows: same name if still free (else the next free one),
    /// in numeric order. With no room left its windows join the shown workspace.
    mutating func reopen(_ group: UUID, avoiding other: Set<String>) {
        guard let g = closedLanes.first(where: { $0.id == group }) else { return }
        let free = available(avoiding: other)
        guard lanes.count < Self.maxLanes, let ws = free.contains(g.ws) ? g.ws : free.first else {
            for id in g.ids { place(id, inLane: activeLane) }
            return
        }
        close.removeAll { g.ids.contains($0) }
        for id in g.ids { origin[id] = nil }
        closedLanes.removeAll { $0.id == group }
        lanes.insert(SortLane(ws: ws, name: g.name, layout: g.layout, ids: g.ids), at: lanes.firstIndex { Self.order(ws, $0.ws) } ?? lanes.count)
    }

    /// Takes a lane away. Its windows go to the lane before it, or after it for the first.
    /// Returns the lane they moved to (as its index after the removal) and how many moved.
    mutating func removeLane(at i: Int) -> (target: Int, moved: Int)? {
        guard lanes.count > 1, lanes.indices.contains(i) else { return nil }
        let moved = lanes[i].ids
        let target = i > 0 ? i - 1 : 1
        lanes[target].ids += moved
        lanes.remove(at: i)
        return (i > 0 ? i - 1 : 0, moved.count)
    }

    mutating func cycleLayout(of lane: Int, by delta: Int, in layouts: [Layout]) {
        guard lanes.indices.contains(lane), !layouts.isEmpty else { return }
        let i = layouts.firstIndex(of: lanes[lane].layout) ?? -1
        lanes[lane].layout = layouts[((i + delta) % layouts.count + layouts.count) % layouts.count]
    }

    /// Moves a window up or down inside its lane (top is the main window).
    mutating func reorder(_ id: CGWindowID, by delta: Int) {
        if let i = close.firstIndex(of: id) {
            let j = i + delta
            if close.indices.contains(j) { close.swapAt(i, j) }
        } else if let l = lane(of: id), let i = lanes[l].ids.firstIndex(of: id) {
            let j = i + delta
            if lanes[l].ids.indices.contains(j) { lanes[l].ids.swapAt(i, j) }
        }
    }

    mutating func moveToTop(_ id: CGWindowID) {
        guard let l = lane(of: id) else { return }
        place(id, inLane: l, at: 0)
    }
}

/// A plan for one display, as the window manager applies it.
struct SortApply {
    let display: String
    /// Workspace name, label, layout and windows (main first) per lane.
    var lanes: [(name: String, label: String, layout: Layout, ids: [CGWindowID])]
    /// Windows put in Close: hidden for now, closed when the panel finishes.
    var close: [CGWindowID]
    /// Workspaces the display had that the plan no longer uses.
    var dropped: [String]
}

extension SortPlan {
    var applied: SortApply {
        SortApply(display: display, lanes: lanes.map { ($0.ws, $0.name.trimmingCharacters(in: .whitespaces), $0.layout, $0.ids) },
                  close: close, dropped: Array(claimed.union(existing)))
    }
}

// MARK: - Task categories

enum SortCategory: String, CaseIterable {
    case code = "Code", web = "Web", chat = "Chat", media = "Media", files = "Files"

    static let all = allCases

    private static let table: [SortCategory: [String]] = [
        .code: ["com.apple.dt.", "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92", "dev.zed.", "com.jetbrains.", "com.sublimetext.", "net.kovidgoyal.kitty",
                "com.github.wez.wezterm", "org.alacritty", "co.zeit.hyper", "com.panic.Nova", "com.apple.ScriptEditor2",
                "com.github.GitHubClient", "com.postmanlabs.", "com.exafunction.windsurf", "com.microsoft.VSCodeInsiders"],
        .web: ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.", "org.mozilla.", "app.zen-browser.",
               "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.", "com.vivaldi.Vivaldi", "org.chromium.Chromium"],
        .chat: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.apple.mail", "com.hnc.Discord", "com.microsoft.teams", "com.microsoft.teams2",
                "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "us.zoom.xos", "com.apple.FaceTime", "com.readdle.",
                "com.microsoft.Outlook", "org.whispersystems.signal-desktop", "com.facebook.archon"],
        .media: ["com.apple.Music", "com.spotify.client", "com.apple.Preview", "com.apple.Photos", "com.figma.Desktop",
                 "com.apple.TV", "com.apple.podcasts", "com.adobe.", "com.apple.QuickTimePlayerX", "org.videolan.vlc",
                 "com.pixelmatorteam.", "com.bohemiancoding.sketch3"],
    ]

    static func of(_ bundleID: String?) -> SortCategory {
        guard let b = bundleID else { return .files }
        for c in [SortCategory.code, .web, .chat, .media] where table[c]!.contains(where: { $0.hasSuffix(".") ? b.hasPrefix($0) : b == $0 || b.hasPrefix($0 + ".") }) {
            return c
        }
        return .files
    }
}
