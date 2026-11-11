import AppKit

package struct WorkspaceSummary {
    package struct Entry {
        package let name: String
        package let windows: Int
        package let shown: Bool
    }

    package let current: String?
    package let all: [Entry]
}

package struct MenuBarState {
    package let workspace: String?
    package let layout: Layout
    package let pids: [pid_t]
}

extension WindowManager {
    package func isShown(_ workspace: String?) -> Bool { model.isShown(workspace) }

    package func workspaceSort(_ first: String, _ second: String) -> Bool {
        switch (Int(WorkspaceKey.number(first)), Int(WorkspaceKey.number(second))) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return first < second
        }
    }

    package var currentWorkspace: String? {
        guard let screen = currentScreen() else { return nil }
        if let request = nativeDesktop.requested, request.display == screen.uuid, isVirtual(request.workspace) {
            return request.workspace
        }
        return virtualShown[screen.uuid]
    }

    package func workspaceSummary() -> WorkspaceSummary {
        guard config.virtualWorkspaces, isStarted else { return WorkspaceSummary(current: nil, all: []) }
        var counts: [String: Int] = [:]
        for (id, workspace) in workspaceOf where windows[id] != nil && isVirtual(workspace) && !isPending(workspace) {
            counts[workspace, default: 0] += 1
        }
        var names = Set(counts.keys).union(desktops.nativeCatalog.entries.map(\.name))
            .union(virtualShown.values).sorted(by: workspaceSort)
        if config.workspacesPerDisplay, let display = currentScreen()?.uuid {
            names = desktops.nativeCatalog.entries(on: display).map(\.name)
        }
        let showing = Set(virtualShown.values)
        return WorkspaceSummary(
            current: currentWorkspace.map(workspaceNumber),
            all: names.map {
                WorkspaceSummary.Entry(name: workspaceNumber($0), windows: counts[$0] ?? 0, shown: showing.contains($0))
            }
        )
    }

    package func menuBarState() -> MenuBarState? {
        guard isStarted, let screen = currentScreen() else { return nil }
        let shownWorkspace = shown[screen.uuid]
        let workspace: String?
        if config.virtualWorkspaces {
            workspace = virtualShown[screen.uuid].map(workspaceNumber)
        } else if let list = Spaces.list(display: screen.uuid), let cur = list.current,
                  let index = list.desktops.firstIndex(of: cur) {
            workspace = String(index + 1)
        } else {
            workspace = nil
        }
        let here = order.filter { workspaceOf[$0] == shownWorkspace && present.contains($0) }.compactMap { windows[$0] }
        var seen = Set<pid_t>()
        let pids = (here.filter { !$0.isFloating } + here.filter(\.isFloating)).map(\.pid)
            .filter { seen.insert($0).inserted }
        return MenuBarState(workspace: workspace, layout: state(for: screen).layout, pids: pids)
    }

    package func resolveWorkspace(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let cur = currentWorkspace ?? "1"
        if trimmed.isEmpty { return nil }
        if lower == "previous" { return currentScreen().flatMap { previousWorkspace[$0.uuid] } }
        if lower.hasPrefix("name:") { return String(trimmed.dropFirst(5)) }
        for prefix in ["r", "m", ""] where lower.hasPrefix(prefix + "+") || lower.hasPrefix(prefix + "-") {
            guard let delta = Int(lower.dropFirst(prefix.count).replacingOccurrences(of: "+", with: "")) else { break }
            if let name = desktops.nativeCatalog.step(from: cur, by: delta) { return name }
            let occupied = workspaceOf.contains { $0.value == cur && windows[$0.key] != nil }
            let display = desktops.nativeCatalog.entry(cur)?.display ?? currentScreen()?.uuid ?? ""
            return delta > 0 && occupied && config.removesEmptyWorkspaces
                ? desktops.nativeCatalog.freeNumber(on: display) : nil
        }
        if lower.hasPrefix("e+") || lower.hasPrefix("e-"),
           let delta = Int(lower.dropFirst(1).replacingOccurrences(of: "+", with: "")) {
            let occupied = Set(workspaceOf.values).union(virtualShown.values)
                .filter { isVirtual($0) && !isPending($0) }
                .sorted(by: workspaceSort)
            return Self.step(occupied, from: cur, by: delta, sortedBy: workspaceSort)
        }
        if config.workspacesPerDisplay, let number = Int(trimmed), number >= 1, let display = currentScreen()?.uuid {
            return WorkspaceKey.make(String(number), on: display, perDisplay: true)
        }
        return trimmed
    }

    package static func step(_ sorted: [String], from current: String, by delta: Int,
                             sortedBy before: (String, String) -> Bool) -> String? {
        guard !sorted.isEmpty else { return nil }
        let index = sorted.firstIndex(of: current) ?? {
            let next = sorted.firstIndex { before(current, $0) } ?? sorted.count
            return delta > 0 ? next - 1 : next
        }()
        let offset = delta % sorted.count
        return sorted[((index + offset) % sorted.count + sorted.count) % sorted.count]
    }

    package func workspaceNumber(_ workspace: String) -> String { WorkspaceKey.number(workspace) }

    package func showWorkspaceNumber(_ number: String) {
        if let workspace = resolveWorkspace(number) { showWorkspace(workspace) }
    }

    package func isVirtual(_ workspace: String?) -> Bool { workspace.map { !$0.hasPrefix(Self.spacePrefix) } ?? false }

    package nonisolated static let spacePrefix = "space:"
    package nonisolated static func spaceWorkspace(display uuid: String, space: UInt64) -> String {
        "\(spacePrefix)\(uuid):\(space)"
    }

    package nonisolated static let pendingPrefix = "sort-close:"
    package func isPending(_ workspace: String?) -> Bool { workspace?.hasPrefix(Self.pendingPrefix) == true }

    @discardableResult
    package func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        let timing = TilingTiming("reconcile", windows: present.count)
        defer { timing.finish() }
        if config.virtualWorkspaces { return syncNativeWorkspaces(screens: screens, present: present) }
        let held = desktops.movingToSpace || NSEvent.pressedMouseButtons & 1 != 0
        let spaces = Spaces.recentSnapshot()
        let observation = WorkspaceObservation(
            displays: screens.map {
                .init(id: $0.uuid, frame: $0.frame, space: backend.currentSpace(display: $0.uuid),
                      spaces: Set(spaces?.list(display: $0.uuid)?.ids ?? []))
            },
            frames: windows.mapValues(\.cachedFrame), present: present,
            held: held ? present : nativeMoves.movingIDs.union(present.filter { animator.isBusy($0) }),
            fullscreen: fullscreenSpaces())
        let plan = WorkspaceReconciliation.reconcile(observation, model: model, virtual: config.virtualWorkspaces,
                                                     homeSpace: desktops.homeSpace, displayOf: displayOf)
        model = plan.model
        desktops.homeSpace = plan.homeSpace
        displayOf = plan.displayOf
        return plan
    }

    package func fullscreenSpaces() -> [CGWindowID: UInt64] {
        var found: [CGWindowID: UInt64] = [:]
        let stillFullscreen = Set(scanner.results.values.flatMap(\.fullscreen))
        leavingFullscreen = leavingFullscreen.filter {
            stillFullscreen.contains($0.key) && Date().timeIntervalSince($0.value) < 3
        }
        for scan in scanner.results.values {
            for id in scan.fullscreen
            where windows[id] != nil && !scan.minimized.contains(id) && leavingFullscreen[id] == nil {
                if let spaces = scanner.desktop.spaces[id], spaces.count == 1, let space = spaces.first {
                    found[id] = space
                }
            }
        }
        return found
    }

    package func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        updateNativeCatalog(backend.screens())
        refresh()
        surface.showHUD("CatWM controls this Desktop", on: currentScreen()?.nsScreen)
    }
}
