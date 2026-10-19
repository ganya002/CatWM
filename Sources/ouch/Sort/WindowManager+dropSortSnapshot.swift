import AppKit

extension WindowManager {
    func dropSortSnapshot() { sortSnapshot = nil }

    func sortDisplays() -> [SortDisplay] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        guard let first = screens.first else { return [] }
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in ([focusedWindow()?.id].compactMap { $0 } + focusOrder).enumerated() where rank[id] == nil { rank[id] = i }
        for (i, info) in CGWindowInfo.onScreen().enumerated() where rank[info.id] == nil { rank[info.id] = 1000 + i }
        func home(_ id: CGWindowID) -> String { workspaceOf[id].flatMap { monitorOf[$0] } ?? first.uuid }
        let tiledIDs = order.filter { isSortable($0, screens: screens) && windows[$0]?.isFloating == false && isVirtual(workspaceOf[$0]) && !isPending(workspaceOf[$0]) }
        let names = screens.map(Self.shortName)
        var shorts = names
        for (i, name) in names.enumerated() where names.filter({ $0 == name }).count > 1 {
            shorts[i] = "\(name) \(names[..<i].filter { $0 == name }.count + 1)"
        }
        return screens.enumerated().map { n, s in
            let mine = tiledIDs.filter { home($0) == s.uuid }
            let items = mine.compactMap { sortItem($0, rank: rank) }
            let fullscreen = model.fullscreenHost.filter { monitorOf[$0.key] == s.uuid }.values
                .sorted { (rank[$0] ?? 2000, $0) < (rank[$1] ?? 2000, $1) }
                .compactMap { sortItem($0, rank: rank) }
            let active = virtualShown[s.uuid]
            var names = Set(mine.compactMap { workspaceOf[$0] })
            if let active { names.insert(active) }
            let spaces = names.sorted(by: workspaceSort).map { name in
                SortWorkspace(name: name, label: labels[name] ?? "", layout: states[name]?.layout ?? config.layouts.first ?? .tall,
                              ratio: states[name]?.ratio ?? 0.5, mainCount: states[name]?.mainCount ?? 1,
                              ids: mine.filter { workspaceOf[$0] == name })
            }
            let taken = Set(monitorOf.filter { $0.value != s.uuid && isVirtual($0.key) && !isPending($0.key) }.keys)
                .union(virtualShown.filter { $0.key != s.uuid }.values)
                .union(tiledIDs.filter { home($0) != s.uuid }.compactMap { workspaceOf[$0] })
            return SortDisplay(id: s.uuid, name: s.ns.localizedName, short: shorts[n], isLaptop: s.isBuiltin,
                               aspect: s.frame.width / max(s.frame.height, 1), screen: s.ns, items: items, fullscreen: fullscreen, workspaces: spaces,
                               active: active, taken: taken)
        }
    }

    func isSortable(_ id: CGWindowID, screens: [Screen]) -> Bool {
        if present.contains(id) { return true }
        guard let w = windows[id], !w.minimized, !w.fullscreen, NSRunningApplication(processIdentifier: w.pid)?.isHidden != true,
              let uuid = workspaceOf[id].flatMap({ monitorOf[$0] }), let home = homeSpace[uuid],
              let screen = screens.first(where: { $0.uuid == uuid }), !isOnHomeSpace(screen) else { return false }
        return scanner.desktop.spaces[id]?.contains(home) == true
    }

    func sortItem(_ id: CGWindowID, rank: [CGWindowID: Int]) -> SortItem? {
        guard let w = windows[id] else { return nil }
        let app = NSRunningApplication(processIdentifier: w.pid)
        let title = w.title ?? ""
        return SortItem(id: id, title: title.isEmpty ? "Untitled" : title, app: app?.localizedName ?? w.bundleID ?? "App",
                        bundleID: w.bundleID, icon: app?.icon, recency: rank[id] ?? 2000)
    }

    static func shortName(_ s: Screen) -> String {
        if s.isBuiltin { return "Built-in" }
        let words = s.ns.localizedName.split(separator: " ").filter { $0.lowercased() != "display" }
        return words.isEmpty ? s.ns.localizedName : words.joined(separator: " ")
    }

    func beginSort() {
        sortSnapshot = SortSnapshot(model: model.snapshot(), labels: labels, focused: focusedWindow()?.id)
        sortSession = true
    }

    func leaveFullscreen(_ id: CGWindowID, to ws: String) {
        guard let w = windows[id], w.element.set("AXFullScreen", kCFBooleanFalse) else {
            Log.info("sort: \(id) refused to leave full screen")
            return
        }
        Log.info("sort: \(id) leaves full screen for workspace \(ws)")
        model.assign(id, to: ws)
        model.fullscreenHost = model.fullscreenHost.filter { $0.value != id }
        leavingFullscreen[id] = Date()
        scheduleRefresh(after: 0.8)
    }

    func liveWindowIDs() -> Set<CGWindowID> { Set(windows.keys) }

    func liveSort(_ plans: [SortApply]) {
        guard config.virtualWorkspaces, isStarted, sortSession else { return }
        let fullscreen = Set(model.fullscreenHost.values)
        let planned = plans.flatMap { $0.lanes.flatMap(\.ids) }.filter { windows[$0] != nil && !fullscreen.contains($0) }
        let moving = Set(planned)
        let kept = Set(plans.flatMap { $0.lanes.map(\.name) })
        var gone: [String: Set<String>] = [:]
        for p in plans {
            gone[p.display] = Set(p.dropped.filter { !kept.contains($0) && (monitorOf[$0] == nil || monitorOf[$0] == p.display) })
        }
        var landing: [String: String] = [:]
        for p in plans {
            let names = Set(p.lanes.map(\.name))
            let land = virtualShown[p.display].flatMap { names.contains($0) ? $0 : nil }
                ?? (p.lanes.first { lane in lane.ids.contains { windows[$0] != nil && !fullscreen.contains($0) } } ?? p.lanes.first)?.name
            guard let land else { continue }
            landing[p.display] = land
            let dropped = gone[p.display] ?? []
            for (id, ws) in workspaceOf where dropped.contains(ws) && !moving.contains(id) { model.assign(id, to: land) }
        }
        for p in plans {
            for lane in p.lanes {
                monitorOf[lane.name] = p.display
                labels[lane.name] = lane.label.isEmpty ? nil : lane.label
                let st = state(workspace: lane.name)
                st.layout = lane.layout
                st.zoomed = nil
                for id in lane.ids where windows[id] != nil && !fullscreen.contains(id) { model.assign(id, to: lane.name) }
            }
            for name in gone[p.display] ?? [] { labels[name] = nil }
            let hidden = Self.pendingPrefix + p.display
            monitorOf[hidden] = p.display
            for id in p.close where windows[id] != nil { model.assign(id, to: hidden) }
        }
        order = order.filter { !moving.contains($0) } + planned
        lastFocused = lastFocused.filter { !moving.contains($0.value) }
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (display, ws) in landing where virtualShown[display] != ws { showWorkspace(ws, focus: false) }
        refresh()
    }

    func finishSort(closing ids: [CGWindowID], goTo: String?, focus: Bool, opening fullscreen: CGWindowID? = nil,
                    leavingFullscreen moves: [CGWindowID: String] = [:]) {
        sortSession = false
        guard config.virtualWorkspaces, isStarted else { return releasePending() }
        let closing = ids.filter { windows[$0] != nil }
        Log.info("sort: finishing, \(ids.count) window(s) marked to close (\(closing.count) still known), goTo=\(goTo ?? "-") focus=\(focus)")
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (id, ws) in moves { leaveFullscreen(id, to: ws) }
        if let id = fullscreen, let w = windows[id] {
            self.focus(w)
        } else if let ws = goTo {
            let main = order.first { workspaceOf[$0] == ws && present.contains($0) && !closing.contains($0) && windows[$0]?.isFloating == false }
            showWorkspace(ws, focusing: main.flatMap { windows[$0] })
        } else if focus {
            let candidates = [sortSnapshot?.focused].compactMap { $0 } + order
            if let id = candidates.first(where: { visible.contains($0) && !closing.contains($0) }), let w = windows[id] { self.focus(w) }
        }
        closingNow.formUnion(closing)
        closingApps.formUnion(closing.compactMap { windows[$0]?.pid })
        releasePending()
        if !closing.isEmpty { closeMarked(closing, attempt: 0) }
    }

}
