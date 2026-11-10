import AppKit
import CatWMKit

extension WindowManager {
    func closeMarked(_ ids: [CGWindowID], attempt: Int) {
        var pressed: [CGWindowID] = []
        for id in ids {
            guard let window = windows[id], window.isValidUnlessStalled else { continue }
            let name = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "pid \(window.pid)"
            closeAndSort.lastClose = Date()
            var outcome = window.close()
            if outcome != "pressed", attempt > 0, focusedWindow()?.id == id {
                outcome += window.closeFromMenu() ? ", menu Close Window chosen" : ", no menu item"
            }
            Log.info("sort: close \(id) \(name) frame=\(window.cachedFrame) try \(attempt + 1): \(outcome)")
            pressed.append(id)
        }
        guard !pressed.isEmpty else { return stopClosing(ids) }
        if attempt >= 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.forceClose(pressed.filter { self.windows[$0]?.isValidUnlessStalled == true })
                self.stopClosing(ids)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            var left = pressed.filter { self.windows[$0]?.isValidUnlessStalled == true }
            Log.info("sort: \(pressed.count - left.count) of \(pressed.count) closed after try \(attempt + 1)")
            let sheeted = Set(left.filter { self.windows[$0].map(Self.hasSheet) ?? false })
            let forced = self.forceClose(left.filter { !sheeted.contains($0) })
            left.removeAll { forced.contains($0) }
            if !forced.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.stopClosing(Array(forced))
                }
            }
            stopClosing(Self.shownAfterTry(ids, left: left, forced: forced, sheeted: sheeted))
            guard !left.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.closeMarked(left, attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    func forceClose(_ ids: [CGWindowID]) -> Set<CGWindowID> {
        var forced: Set<CGWindowID> = []
        let closing = Set(ids)
        var live: [CGWindowID: Bool] = [:]
        func isLive(_ window: Window) -> Bool {
            if let known = live[window.id] { return known }
            let answer = window.isValidUnlessStalled
            live[window.id] = answer
            return answer
        }
        for id in ids {
            guard let window = windows[id], isLive(window) else { continue }
            let hasSheet = Self.hasSheet(window)
            let others = windows.values.contains {
                $0.pid == window.pid && $0.id != id && !closing.contains($0.id) && isLive($0)
            }
            let name = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "pid \(window.pid)"
            if hasSheet || others {
                Log.info("sort: not forcing \(id) \(name): \(hasSheet ? "sheet up" : "app has other windows")")
                continue
            }
            Log.info("sort: force quitting \(name) for window \(id)")
            closeAndSort.lastClose = Date()
            NSRunningApplication(processIdentifier: window.pid)?.forceTerminate()
            forced.insert(id)
        }
        return forced
    }

    static func shownAfterTry(_ ids: [CGWindowID], left: [CGWindowID], forced: Set<CGWindowID>,
                              sheeted: Set<CGWindowID>) -> [CGWindowID] {
        ids.filter { !forced.contains($0) && (sheeted.contains($0) || !left.contains($0)) }
    }

    static func reportsNoWindows(_ error: AXError, _ value: CFTypeRef?) -> Bool {
        switch error {
        case .success: (value as? [AXUIElement])?.isEmpty == true
        case .noValue: true
        default: false
        }
    }

    private static func hasNoWindows(_ pid: pid_t) -> Bool {
        guard !AXStalls.shared.isStalled(pid) else { return reportsNoWindows(.cannotComplete, nil) }
        var value: CFTypeRef?
        let app = axApp(pid)
        let error = app.noted { AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) }
        return reportsNoWindows(error, value)
    }

    static func hasSheet(_ window: Window) -> Bool {
        guard !AXStalls.shared.isStalled(window.pid) else { return mayShowSheet(.stalled) }
        switch window.element.readElements(kAXChildrenAttribute) {
        case .stalled: return mayShowSheet(.stalled)
        case .missing: return mayShowSheet(.missing)
        case .value(let children): return mayShowSheet(.value(children.map { $0.readString(kAXRoleAttribute) }))
        }
    }

    static func mayShowSheet(_ roles: AXRead<[AXRead<String>]>) -> Bool {
        switch roles {
        case .stalled: return true
        case .missing: return false
        case .value(let roles):
            return roles.contains {
                if case .stalled = $0 { return true }
                return $0.value == kAXSheetRole
            }
        }
    }

    func stopClosing(_ ids: [CGWindowID]) {
        closeAndSort.closingNow.subtract(ids)
        releasePending(Set(ids))
        quitWindowless()
    }

    func quitWindowless() {
        for pid in closeAndSort.closingApps {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                closeAndSort.closingApps.remove(pid)
                continue
            }
            guard app.activationPolicy == .regular, app.bundleIdentifier != "com.apple.finder" else {
                closeAndSort.closingApps.remove(pid)
                continue
            }
            let known = windows.values.contains { $0.pid == pid && $0.isValidUnlessStalled }
            guard !known, Self.hasNoWindows(pid) else { continue }
            closeAndSort.closingApps.remove(pid)
            let name = app.bundleIdentifier ?? "pid \(pid)"
            Log.info("sort: \(name) has no windows left; quitting it")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !app.isTerminated, Self.hasNoWindows(pid) else { return }
                Log.info("sort: \(name) didn't quit; force quitting it")
                app.forceTerminate()
            }
        }
    }

    func revertSort() {
        closeAndSort.sortSession = false
        if let snapshot = closeAndSort.sortSnapshot { restoreSort(snapshot) }
        closeAndSort.sortSnapshot = nil
        releasePending()
    }

    func releasePending(_ ids: Set<CGWindowID>? = nil) {
        let waiting = workspaceOf.filter {
            isPending($0.value) && (ids?.contains($0.key) ?? !closeAndSort.closingNow.contains($0.key))
        }
        let screens = backend.screens()
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
        closeAndSort.sortSession = false
        releasePending()
    }

    @discardableResult
    func undoSort() -> Bool {
        guard config.virtualWorkspaces, !closeAndSort.sortSession,
              let snapshot = closeAndSort.sortSnapshot else { return false }
        closeAndSort.sortSnapshot = nil
        restoreSort(snapshot)
        return true
    }

    func restoreSort(_ snapshot: SortSnapshot) {
        desktops.nativeDroppedWorkspaces = []
        let saved = snapshot.model
        var moves: [CGWindowID: String] = [:]
        for (id, workspace) in saved.workspaceOf where windows[id] != nil && !closeAndSort.closingNow.contains(id) {
            if workspaceOf[id] != workspace, let window = windows[id] {
                moveNativeWindow(window, to: workspace, follow: false)
            }
            moves[id] = workspace
        }
        model.assign(moves)
        restoreSortTabs(saved.tabs)
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
            workspaceState.zoomed = savedState.zoomed
        }
        for (workspace, id) in saved.lastFocused
        where lastFocused[workspace] == nil && windows[id] != nil && workspaceOf[id] == workspace {
            lastFocused[workspace] = id
        }
        corrections = [:]
        closeAndSort.quietWorkspaceHUD = true
        defer { closeAndSort.quietWorkspaceHUD = false }
        for (display, workspace) in saved.virtualShown where virtualShown[display] != workspace {
            showWorkspace(workspace, focus: false)
        }
        refresh()
    }

    private func restoreSortTabs(_ saved: TabGroups) {
        for group in saved.groups {
            let members = group.members.filter { windows[$0] != nil && workspaceOf[$0] == workspaceOf[group.active] }
            guard members.count > 1, tabs.group(of: members[0])?.members != members else { continue }
            members.forEach { model.leaveTab($0) }
            model.restoreTabs(members, active: group.active)
        }
    }

    func tiledCount(in workspace: String) -> Int {
        let screens = backend.screens()
        return order.reduce(0) { total, id in
            total + (workspaceOf[id] == workspace && windows[id]?.isFloating == false && !tabs.isBehind(id)
                && (present.contains(id) || isSortable(id, screens: screens)) ? 1 : 0)
        }
    }
}
