import AppKit
import CatWMKit

extension WindowManager {
    func dropSortSnapshot() { closeAndSort.sortSnapshot = nil }

    func sortDisplays() -> [SortDisplay] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = backend.screens()
        guard let first = screens.first else { return [] }
        var rank: [CGWindowID: Int] = [:]
        let focusRanked = [focusedWindow()?.id].compactMap(\.self) + focusOrder
        for (i, id) in focusRanked.enumerated() where rank[id] == nil { rank[id] = i }
        for (i, info) in CGWindowInfo.onScreen().enumerated() where rank[info.id] == nil { rank[info.id] = 1000 + i }
        func home(_ id: CGWindowID) -> String { workspaceOf[id].flatMap { monitorOf[$0] } ?? first.uuid }
        let tiledIDs = order.filter {
            isSortable($0, screens: screens)
                && windows[$0]?.isFloating == false
                && isVirtual(workspaceOf[$0])
                && !isPending(workspaceOf[$0])
        }
        let names = screens.map(Self.shortName)
        var shorts = names
        for (i, name) in names.enumerated() where names.filter({ $0 == name }).count > 1 {
            shorts[i] = "\(name) \(names[..<i].filter { $0 == name }.count + 1)"
        }
        return screens.enumerated().compactMap { index, screen in
            guard let nsScreen = screen.nsScreen else { return nil }
            let mine = tiledIDs.filter { home($0) == screen.uuid }
            let items = mine.compactMap { sortItem($0, rank: rank) }
            let fullscreen = model.fullscreenHost.filter { monitorOf[$0.key] == screen.uuid }.values
                .sorted { (rank[$0] ?? 2000, $0) < (rank[$1] ?? 2000, $1) }
                .compactMap { sortItem($0, rank: rank) }
            let active = virtualShown[screen.uuid]
            let elsewhere = monitorOf.filter { $0.value != screen.uuid && isVirtual($0.key) && !isPending($0.key) }
            let taken = Set(elsewhere.keys)
                .union(virtualShown.filter { $0.key != screen.uuid }.values)
                .union(tiledIDs.filter { home($0) != screen.uuid }.compactMap { workspaceOf[$0] })
            return SortDisplay(id: screen.uuid, name: screen.name, short: shorts[index],
                               isLaptop: screen.isBuiltin, aspect: screen.frame.width / max(screen.frame.height, 1),
                               screen: nsScreen, items: items, fullscreen: fullscreen,
                               workspaces: sortWorkspaces(mine, active: active, display: screen.uuid),
                               active: active, taken: taken, perDisplay: config.workspacesPerDisplay,
                               tabs: tabs.groups.map(\.activeFirst))
        }
    }

    private func sortWorkspaces(_ mine: [CGWindowID], active: String?, display: String) -> [SortWorkspace] {
        var names = Set(mine.compactMap { workspaceOf[$0] })
        names.formUnion(desktops.nativeCatalog.entries.filter { $0.display == display }.map(\.name))
        if let active { names.insert(active) }
        names.subtract(desktops.nativeDroppedWorkspaces)
        return names.sorted(by: workspaceSort).map { name in
            SortWorkspace(name: name, label: labels[name] ?? "",
                          layout: states[name]?.layout ?? config.layouts.first ?? .tall,
                          ratio: states[name]?.ratio ?? 0.5, mainCount: states[name]?.mainCount ?? 1,
                          ids: mine.filter { workspaceOf[$0] == name })
        }
    }

    func isSortable(_ id: CGWindowID, screens: [Screen]) -> Bool {
        if present.contains(id) { return true }
        if config.virtualWorkspaces {
            guard let window = windows[id], !window.minimized, !window.fullscreen,
                  NSRunningApplication(processIdentifier: window.pid)?.isHidden != true,
                  let name = workspaceOf[id], let entry = desktops.nativeCatalog.entry(name) else { return false }
            return scanner.desktop.spaces[id]?.contains(entry.space) == true
                || nativeMoves.confirms(id, on: entry.space)
        }
        guard let window = windows[id], !window.minimized, !window.fullscreen,
              NSRunningApplication(processIdentifier: window.pid)?.isHidden != true,
              let uuid = workspaceOf[id].flatMap({ monitorOf[$0] }), let home = desktops.homeSpace[uuid],
              let screen = screens.first(where: { $0.uuid == uuid }), !isOnHomeSpace(screen) else { return false }
        return scanner.desktop.spaces[id]?.contains(home) == true
    }

    func sortItem(_ id: CGWindowID, rank: [CGWindowID: Int]) -> SortItem? {
        guard let window = windows[id] else { return nil }
        let app = NSRunningApplication(processIdentifier: window.pid)
        let title = window.title ?? ""
        return SortItem(id: id, title: title.isEmpty ? "Untitled" : title,
                        app: app?.localizedName ?? window.bundleID ?? "App",
                        bundleID: window.bundleID, icon: AppIcons.shared.icon(for: window.pid),
                        recency: rank[id] ?? 2000)
    }

    static func shortName(_ screen: Screen) -> String {
        if screen.isBuiltin { return "Built-in" }
        let words = screen.name.split(separator: " ").filter { $0.lowercased() != "display" }
        return words.isEmpty ? screen.name : words.joined(separator: " ")
    }

    func beginSort() {
        desktops.nativeSortNames = []
        closeAndSort.sortSnapshot = SortSnapshot(model: model.snapshot(), labels: labels, focused: focusedWindow()?.id)
        closeAndSort.sortSession = true
    }

    func liveWindowIDs() -> Set<CGWindowID> { Set(windows.keys) }

    func liveSort(_ plans: [SortApply]) {
        guard config.virtualWorkspaces, isStarted, closeAndSort.sortSession else { return }
        let fullscreen = Set(model.fullscreenHost.values)
        let planned = plans.flatMap { $0.lanes.flatMap(\.ids) }
            .filter { windows[$0] != nil && !fullscreen.contains($0) }
        let moving = Set(planned)
        let kept = Set(plans.flatMap { $0.lanes.map(\.name) })
        var gone: [String: Set<String>] = [:]
        for apply in plans {
            gone[apply.display] = Set(apply.dropped.filter {
                !kept.contains($0) && (monitorOf[$0] == nil || monitorOf[$0] == apply.display)
            })
        }
        desktops.nativeDroppedWorkspaces.formUnion(gone.values.flatMap(\.self))
        desktops.nativeDroppedWorkspaces.subtract(kept)
        desktops.nativeSortNames.formUnion(kept)
        desktops.nativeSortNames.subtract(desktops.nativeDroppedWorkspaces)
        let landing = landSortDisplays(plans, gone: gone, moving: moving, fullscreen: fullscreen)
        for apply in plans { applySortLanes(apply, gone: gone[apply.display] ?? [], fullscreen: fullscreen) }
        order = order.filter { !moving.contains($0) } + planned
        lastFocused = lastFocused.filter { !moving.contains($0.value) }
        corrections = [:]
        closeAndSort.quietWorkspaceHUD = true
        defer { closeAndSort.quietWorkspaceHUD = false }
        for (display, workspace) in landing where virtualShown[display] != workspace {
            virtualShown[display] = workspace
        }
        refresh()
    }

    private func landSortDisplays(_ plans: [SortApply], gone: [String: Set<String>], moving: Set<CGWindowID>,
                                  fullscreen: Set<CGWindowID>) -> [String: String] {
        var landing: [String: String] = [:]
        for apply in plans {
            let names = Set(apply.lanes.map(\.name))
            let firstLive = apply.lanes.first { lane in
                lane.ids.contains { windows[$0] != nil && !fullscreen.contains($0) }
            }
            let land = virtualShown[apply.display].flatMap { names.contains($0) ? $0 : nil }
                ?? (firstLive ?? apply.lanes.first)?.name
            guard let land else { continue }
            landing[apply.display] = land
            let dropped = gone[apply.display] ?? []
            let stranded = workspaceOf.filter { dropped.contains($0.value) && !moving.contains($0.key) }
            model.assign(stranded.mapValues { _ in land })
        }
        return landing
    }

    private func applySortLanes(_ apply: SortApply, gone: Set<String>, fullscreen: Set<CGWindowID>) {
        var moves: [CGWindowID: String] = [:]
        for lane in apply.lanes {
            monitorOf[lane.name] = apply.display
            labels[lane.name] = lane.label.isEmpty ? nil : lane.label
            let laneState = state(workspace: lane.name)
            laneState.layout = lane.layout
            if let zoomed = laneState.zoomed, !lane.ids.contains(zoomed) { laneState.zoomed = nil }
            for id in lane.ids where windows[id] != nil && !fullscreen.contains(id) { moves[id] = lane.name }
        }
        for name in gone { labels[name] = nil }
        let hidden = Self.pendingPrefix + apply.display
        monitorOf[hidden] = apply.display
        for id in apply.close where windows[id] != nil { moves[id] = hidden }
        model.assign(moves)
        applySortTabs(apply)
    }

    private func applySortTabs(_ apply: SortApply) {
        let laned = Set(apply.lanes.flatMap(\.ids)).filter { windows[$0] != nil }
        let wanted = apply.tabs.map { $0.filter(laned.contains) }.filter { $0.count > 1 }
        for id in laned where tabs.isGrouped(id) && !wanted.contains(where: { $0.contains(id) }) { model.leaveTab(id) }
        for members in wanted {
            let active = tabs.group(of: members[0])?.active
            for (previous, id) in zip(members, members.dropFirst())
            where tabs.group(of: previous)?.members.contains(id) != true {
                model.joinTab(id, onto: previous)
            }
            if let active, members.contains(active) { model.activateTab(active) }
        }
    }

    func finishSortAfterNative(closing ids: [CGWindowID], goTo: String?, focus: Bool, opening fullscreen: CGWindowID?) {
        closeAndSort.sortSession = false
        guard config.virtualWorkspaces, isStarted else { return releasePending() }
        let closing = ids.filter { windows[$0] != nil }
        Log.info("sort: finishing, \(ids.count) window(s) marked to close (\(closing.count) still known), "
            + "goTo=\(goTo ?? "-") focus=\(focus)")
        corrections = [:]
        closeAndSort.quietWorkspaceHUD = true
        defer { closeAndSort.quietWorkspaceHUD = false }
        if let id = fullscreen, let window = windows[id] {
            self.focus(window)
        } else if let workspace = goTo {
            let main = order.first {
                workspaceOf[$0] == workspace && present.contains($0) && !closing.contains($0)
                    && windows[$0]?.isFloating == false
            }
            showWorkspace(workspace, focusing: main.flatMap { windows[$0] })
        } else if focus {
            let candidates = [closeAndSort.sortSnapshot?.focused].compactMap(\.self) + order
            if let id = candidates.first(where: { visible.contains($0) && !closing.contains($0) }),
               let window = windows[id] {
                self.focus(window)
            }
        }
        closeAndSort.closingNow.formUnion(closing)
        closeAndSort.closingApps.formUnion(closing.compactMap { windows[$0]?.pid })
        releasePending()
        if !closing.isEmpty { closeMarked(closing, attempt: 0) }
        commitNativeRemovals()
    }
}
