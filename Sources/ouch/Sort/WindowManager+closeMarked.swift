import AppKit

extension WindowManager {
    func closeMarked(_ ids: [CGWindowID], attempt: Int) {
        var pressed: [CGWindowID] = []
        for id in ids {
            guard let window = windows[id], window.isValid else { continue }
            let name = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "pid \(window.pid)"
            lastClose = Date()
            var outcome = window.close()
            if outcome != "pressed", attempt > 0, focusedWindow()?.id == id {
                outcome += window.closeFromMenu() ? ", menu Close Window chosen" : ", no menu item"
            }
            Log.info("sort: close \(id) \(name) frame=\(window.frame) try \(attempt + 1): \(outcome)")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.stopClosing(Array(forced))
                }
            }
            stopClosing(ids.filter { !forced.contains($0) })
            guard !left.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.closeMarked(left, attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    func forceClose(_ ids: [CGWindowID]) -> Set<CGWindowID> {
        var forced: Set<CGWindowID> = []
        for id in ids {
            guard let window = windows[id], window.isValid else { continue }
            let hasSheet = Self.hasSheet(window)
            let others = windows.values.contains {
                $0.pid == window.pid && $0.id != id && $0.isValid && !ids.contains($0.id)
            }
            let name = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "pid \(window.pid)"
            if hasSheet || others {
                Log.info("sort: not forcing \(id) \(name): \(hasSheet ? "sheet up" : "app has other windows")")
                continue
            }
            Log.info("sort: force quitting \(name) for window \(id)")
            lastClose = Date()
            NSRunningApplication(processIdentifier: window.pid)?.forceTerminate()
            forced.insert(id)
        }
        return forced
    }

    static func hasSheet(_ window: Window) -> Bool {
        window.element.elements(kAXChildrenAttribute).contains { $0.string(kAXRoleAttribute) == kAXSheetRole }
    }

    func stopClosing(_ ids: [CGWindowID]) {
        closingNow.subtract(ids)
        releasePending(Set(ids))
        quitWindowless()
    }

    func quitWindowless() {
        for pid in closingApps {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                closingApps.remove(pid)
                continue
            }
            guard app.activationPolicy == .regular, app.bundleIdentifier != "com.apple.finder" else {
                closingApps.remove(pid)
                continue
            }
            let known = windows.values.contains { $0.pid == pid && $0.isValid }
            guard !known, AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { continue }
            closingApps.remove(pid)
            let name = app.bundleIdentifier ?? "pid \(pid)"
            Log.info("sort: \(name) has no windows left; quitting it")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !app.isTerminated,
                      AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { return }
                Log.info("sort: \(name) didn't quit; force quitting it")
                app.forceTerminate()
            }
        }
    }

    func revertSort() {
        sortSession = false
        if let snapshot = sortSnapshot { restoreSort(snapshot) }
        sortSnapshot = nil
        releasePending()
    }

    func releasePending(_ ids: Set<CGWindowID>? = nil) {
        let waiting = workspaceOf.filter {
            isPending($0.value) && (ids?.contains($0.key) ?? !closingNow.contains($0.key))
        }
        let screens = Screen.all()
        for (id, key) in waiting {
            let display = String(key.dropFirst(Self.pendingPrefix.count))
            model.assign(id, to: virtualShown[display]
                ?? screens.first.flatMap { virtualShown[$0.uuid] }
                ?? screens.first.flatMap { shown[$0.uuid] })
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
        guard config.virtualWorkspaces, !sortSession, let snapshot = sortSnapshot else { return false }
        sortSnapshot = nil
        restoreSort(snapshot)
        return true
    }

    func restoreSort(_ snapshot: SortSnapshot) {
        let saved = snapshot.model
        for (id, workspace) in saved.workspaceOf where windows[id] != nil && !closingNow.contains(id) {
            model.assign(id, to: workspace)
        }
        let known = Set(saved.order)
        order = saved.order.filter { windows[$0] != nil } + order.filter { !known.contains($0) }
        monitorOf = saved.monitorOf
        labels = snapshot.labels
        for name in Array(states.keys) where saved.states[name] == nil { states[name] = nil }
        for (name, savedState) in saved.states {
            let workspaceState = state(workspace: name)
            workspaceState.layout = savedState.layout
            workspaceState.ratio = savedState.ratio.isFinite ? min(0.9, max(0.1, savedState.ratio)) : 0.5
            workspaceState.mainCount = savedState.mainCount
            workspaceState.zoomed = nil
        }
        for (workspace, id) in saved.lastFocused
        where lastFocused[workspace] == nil && windows[id] != nil && workspaceOf[id] == workspace {
            lastFocused[workspace] = id
        }
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (display, workspace) in saved.virtualShown where virtualShown[display] != workspace {
            showWorkspace(workspace, focus: false)
        }
        refresh()
    }

    func tiledCount(in workspace: String) -> Int {
        order.reduce(0) { total, id in
            total + (present.contains(id) && workspaceOf[id] == workspace && windows[id]?.isFloating == false ? 1 : 0)
        }
    }
}
