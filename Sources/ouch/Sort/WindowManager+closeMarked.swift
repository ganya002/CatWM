import AppKit

extension WindowManager {
    func closeMarked(_ ids: [CGWindowID], attempt: Int) {
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
    func forceClose(_ ids: [CGWindowID]) -> Set<CGWindowID> {
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

    static func hasSheet(_ w: Window) -> Bool {
        w.element.elements(kAXChildrenAttribute).contains { $0.string(kAXRoleAttribute) == kAXSheetRole }
    }

    func stopClosing(_ ids: [CGWindowID]) {
        closingNow.subtract(ids)
        releasePending(Set(ids))
        quitWindowless()
    }

    func quitWindowless() {
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

    func releasePending(_ ids: Set<CGWindowID>? = nil) {
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

    func restoreSort(_ snapshot: SortSnapshot) {
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

    func tiledCount(in ws: String) -> Int {
        order.reduce(0) { n, id in n + (present.contains(id) && workspaceOf[id] == ws && windows[id]?.isFloating == false ? 1 : 0) }
    }

}
