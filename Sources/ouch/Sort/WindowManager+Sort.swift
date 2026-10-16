import AppKit

extension WindowManager {

    struct SortSnapshot {
        var model: WorkspaceModel
        var labels: [String: String]
        var focused: CGWindowID?
    }

    func dropSortSnapshot() { sortSnapshot = nil }

    func sortDisplays() -> [SortDisplay] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        guard let first = screens.first else { return [] }
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in ([focusedWindow()?.id].compactMap { $0 } + focusOrder).enumerated() where rank[id] == nil { rank[id] = i }
        for (i, info) in CGWindowInfo.onScreen().enumerated() where rank[info.id] == nil { rank[info.id] = 1000 + i }
        func home(_ id: CGWindowID) -> String { workspaceOf[id].flatMap { monitorOf[$0] } ?? first.uuid }
        let tiledIDs = order.filter { present.contains($0) && windows[$0]?.isFloating == false && isVirtual(workspaceOf[$0]) && !isPending(workspaceOf[$0]) }
        let names = screens.map(Self.shortName)
        var shorts = names
        for (i, name) in names.enumerated() where names.filter({ $0 == name }).count > 1 {
            shorts[i] = "\(name) \(names[..<i].filter { $0 == name }.count + 1)"
        }
        return screens.enumerated().map { n, s in
            let mine = tiledIDs.filter { home($0) == s.uuid }
            let items = mine.compactMap { id -> SortItem? in
                guard let w = windows[id] else { return nil }
                let app = NSRunningApplication(processIdentifier: w.pid)
                let title = w.element.string(kAXTitleAttribute) ?? ""
                return SortItem(id: id, title: title.isEmpty ? "Untitled" : title, app: app?.localizedName ?? w.bundleID ?? "App",
                                bundleID: w.bundleID, icon: app?.icon, recency: rank[id] ?? 2000)
            }
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
                               aspect: s.frame.width / max(s.frame.height, 1), screen: s.ns, items: items, workspaces: spaces,
                               active: active, taken: taken)
        }
    }

    private static func shortName(_ s: Screen) -> String {
        if s.isBuiltin { return "Built-in" }
        let words = s.ns.localizedName.split(separator: " ").filter { $0.lowercased() != "display" }
        return words.isEmpty ? s.ns.localizedName : words.joined(separator: " ")
    }

    func beginSort() {
        sortSnapshot = SortSnapshot(model: model.snapshot(), labels: labels, focused: focusedWindow()?.id)
        sortSession = true
    }

    func liveWindowIDs() -> Set<CGWindowID> { Set(windows.keys) }

    func liveSort(_ plans: [SortApply]) {
        guard config.virtualWorkspaces, isStarted, sortSession else { return }
        let planned = plans.flatMap { $0.lanes.flatMap(\.ids) }.filter { windows[$0] != nil }
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
                ?? (p.lanes.first { lane in lane.ids.contains { windows[$0] != nil } } ?? p.lanes.first)?.name
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
                for id in lane.ids where windows[id] != nil { model.assign(id, to: lane.name) }
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

    func finishSort(closing ids: [CGWindowID], goTo: String?, focus: Bool) {
        sortSession = false
        guard config.virtualWorkspaces, isStarted else { return releasePending() }
        let closing = ids.filter { windows[$0] != nil }
        Log.info("sort: finishing, \(ids.count) window(s) marked to close (\(closing.count) still known), goTo=\(goTo ?? "-") focus=\(focus)")
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        if let ws = goTo {
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

    private func closeMarked(_ ids: [CGWindowID], attempt: Int) {
        var pressed: [CGWindowID] = []
        for id in ids {
            guard let w = windows[id], w.isValid else { continue }
            let name = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "pid \(w.pid)"
            lastClose = Date()
            var outcome = w.close()
            if outcome != "pressed", attempt > 0, focusedWindow()?.id == id { outcome += w.closeFromMenu() ? ", menu Close Window chosen" : ", no menu item" }
            Log.info("sort: close \(id) \(name) frame=\(w.frame) try \(attempt + 1): \(outcome)")
            pressed.append(id)
        }
        guard !pressed.isEmpty else { return stopClosing(ids) }
        if attempt >= 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.forceClose(pressed.filter { self.windows[$0]?.isValid == true })
                self.stopClosing(ids)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            var left = pressed.filter { self.windows[$0]?.isValid == true }
            Log.info("sort: \(pressed.count - left.count) of \(pressed.count) closed after try \(attempt + 1)")
            let forced = self.forceClose(left.filter { self.windows[$0].map { !Self.hasSheet($0) } ?? false })
            left.removeAll { forced.contains($0) }
            if !forced.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.stopClosing(Array(forced)) }
            }
            stopClosing(ids.filter { !forced.contains($0) })
            guard !left.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.closeMarked(left, attempt: attempt + 1) }
        }
    }

    @discardableResult
    private func forceClose(_ ids: [CGWindowID]) -> Set<CGWindowID> {
        var forced: Set<CGWindowID> = []
        for id in ids {
            guard let w = windows[id], w.isValid else { continue }
            let hasSheet = Self.hasSheet(w)
            let others = windows.values.contains { $0.pid == w.pid && $0.id != id && $0.isValid && !ids.contains($0.id) }
            let name = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "pid \(w.pid)"
            if hasSheet || others { Log.info("sort: not forcing \(id) \(name): \(hasSheet ? "sheet up" : "app has other windows")"); continue }
            Log.info("sort: force quitting \(name) for window \(id)")
            lastClose = Date()
            NSRunningApplication(processIdentifier: w.pid)?.forceTerminate()
            forced.insert(id)
        }
        return forced
    }

    private static func hasSheet(_ w: Window) -> Bool {
        w.element.elements(kAXChildrenAttribute).contains { $0.string(kAXRoleAttribute) == kAXSheetRole }
    }

    private func stopClosing(_ ids: [CGWindowID]) {
        closingNow.subtract(ids)
        releasePending(Set(ids))
        quitWindowless()
    }

    private func quitWindowless() {
        for pid in closingApps {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { closingApps.remove(pid); continue }
            guard app.activationPolicy == .regular, app.bundleIdentifier != "com.apple.finder" else { closingApps.remove(pid); continue }
            let known = windows.values.contains { $0.pid == pid && $0.isValid }
            guard !known, AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { continue }
            closingApps.remove(pid)
            let name = app.bundleIdentifier ?? "pid \(pid)"
            Log.info("sort: \(name) has no windows left; quitting it")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !app.isTerminated, AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { return }
                Log.info("sort: \(name) didn't quit; force quitting it")
                app.forceTerminate()
            }
        }
    }

    func revertSort() {
        sortSession = false
        if let u = sortSnapshot { restoreSort(u) }
        sortSnapshot = nil
        releasePending()
    }

    private func releasePending(_ ids: Set<CGWindowID>? = nil) {
        let waiting = workspaceOf.filter { isPending($0.value) && (ids?.contains($0.key) ?? !closingNow.contains($0.key)) }
        let screens = Screen.all()
        for (id, key) in waiting {
            let display = String(key.dropFirst(Self.pendingPrefix.count))
            model.assign(id, to: virtualShown[display] ?? screens.first.flatMap { virtualShown[$0.uuid] } ?? screens.first.flatMap { shown[$0.uuid] })
        }
        let used = Set(workspaceOf.values.filter(isPending))
        for key in monitorOf.keys where isPending(key) && !used.contains(key) { monitorOf[key] = nil }
        guard !waiting.isEmpty else { return }
        corrections = [:]
        refresh()
    }

    func endSort() {
        sortSession = false
        releasePending()
    }

    @discardableResult
    func undoSort() -> Bool {
        guard config.virtualWorkspaces, !sortSession, let u = sortSnapshot else { return false }
        sortSnapshot = nil
        restoreSort(u)
        return true
    }

    private func restoreSort(_ snapshot: SortSnapshot) {
        let u = snapshot.model
        for (id, ws) in u.workspaceOf where windows[id] != nil && !closingNow.contains(id) { model.assign(id, to: ws) }
        let known = Set(u.order)
        order = u.order.filter { windows[$0] != nil } + order.filter { !known.contains($0) }
        monitorOf = u.monitorOf
        labels = snapshot.labels
        for name in Array(states.keys) where u.states[name] == nil { states[name] = nil }
        for (name, l) in u.states {
            let st = state(workspace: name)
            st.layout = l.layout; st.ratio = l.ratio.isFinite ? min(0.9, max(0.1, l.ratio)) : 0.5; st.mainCount = l.mainCount; st.zoomed = nil
        }
        for (ws, id) in u.lastFocused where lastFocused[ws] == nil && windows[id] != nil && workspaceOf[id] == ws { lastFocused[ws] = id }
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (display, ws) in u.virtualShown where virtualShown[display] != ws { showWorkspace(ws, focus: false) }
        refresh()
    }

    private func tiledCount(in ws: String) -> Int {
        order.reduce(0) { n, id in n + (present.contains(id) && workspaceOf[id] == ws && windows[id]?.isFloating == false ? 1 : 0) }
    }

    func shownWorkspaces() -> [(workspace: String, count: Int, screen: NSScreen)] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        let focus = currentScreen()?.uuid
        return (screens.filter { $0.uuid == focus } + screens.filter { $0.uuid != focus }).compactMap { s in
            guard let ws = shown[s.uuid], isVirtual(ws) else { return nil }
            return (ws, tiledCount(in: ws), s.ns)
        }
    }

    func watchCrowding(_ screens: [Screen]) {
        guard config.virtualWorkspaces, tilingEnabled, config.sortNudge > 0,
              screens.contains(where: { s in shown[s.uuid].map { isVirtual($0) && tiledCount(in: $0) > config.sortNudge } ?? false })
        else { crowdWork?.cancel(); crowdWork = nil; return }
        guard crowdWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            crowdWork = nil
            if let hit = shownWorkspaces().first(where: { $0.count > self.config.sortNudge }) {
                SortNudge.shared.offer(workspace: hit.workspace, count: hit.count, on: hit.screen)
            }
        }
        crowdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
