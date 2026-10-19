import AppKit

struct WorkspaceSummary {
    struct Entry {
        let name: String
        let windows: Int
        let shown: Bool
    }

    let current: String?
    let all: [Entry]
}

struct MenuBarState {
    let workspace: String?
    let layout: Layout
    let pids: [pid_t]
}

extension WindowManager {
    func isShown(_ workspace: String?) -> Bool { model.isShown(workspace) }

    func workspaceSort(_ first: String, _ second: String) -> Bool {
        switch (Int(first), Int(second)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return first < second
        }
    }

    var currentWorkspace: String? { currentScreen().flatMap { virtualShown[$0.uuid] } }

    func workspaceSummary() -> WorkspaceSummary {
        guard config.virtualWorkspaces, isStarted else { return WorkspaceSummary(current: nil, all: []) }
        var counts: [String: Int] = [:]
        for (id, workspace) in workspaceOf where windows[id] != nil && isVirtual(workspace) && !isPending(workspace) {
            counts[workspace, default: 0] += 1
        }
        let names = Set(counts.keys).union(virtualShown.values).sorted(by: workspaceSort)
        let showing = Set(virtualShown.values)
        let current = currentScreen().flatMap { virtualShown[$0.uuid] }
        return WorkspaceSummary(
            current: current,
            all: names.map { WorkspaceSummary.Entry(name: $0, windows: counts[$0] ?? 0, shown: showing.contains($0)) }
        )
    }

    func menuBarState() -> MenuBarState? {
        guard isStarted, let screen = currentScreen() else { return nil }
        let shownWorkspace = shown[screen.uuid]
        let workspace: String?
        if config.virtualWorkspaces {
            workspace = virtualShown[screen.uuid]
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

    func resolveWorkspace(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let cur = currentWorkspace ?? "1"
        if trimmed.isEmpty { return nil }
        if lower == "previous" { return currentScreen().flatMap { previousWorkspace[$0.uuid] } }
        if lower.hasPrefix("name:") { return String(trimmed.dropFirst(5)) }
        for prefix in ["r", "m", ""] where lower.hasPrefix(prefix + "+") || lower.hasPrefix(prefix + "-") {
            guard let delta = Int(lower.dropFirst(prefix.count).replacingOccurrences(of: "+", with: "")) else { break }
            return String(max(1, (Int(cur) ?? 1) + delta))
        }
        if lower.hasPrefix("e+") || lower.hasPrefix("e-"),
           let delta = Int(lower.dropFirst(1).replacingOccurrences(of: "+", with: "")) {
            let occupied = Set(workspaceOf.values).union(virtualShown.values)
                .filter { isVirtual($0) && !isPending($0) }
                .sorted(by: workspaceSort)
            guard !occupied.isEmpty else { return nil }
            let i = occupied.firstIndex(of: cur) ?? 0
            return occupied[((i + delta) % occupied.count + occupied.count) % occupied.count]
        }
        return trimmed
    }

    func isVirtual(_ workspace: String?) -> Bool { workspace.map { !$0.hasPrefix(Self.spacePrefix) } ?? false }

    static let spacePrefix = "space:"
    static func spaceWorkspace(display uuid: String, space: UInt64) -> String { "\(spacePrefix)\(uuid):\(space)" }

    static let pendingPrefix = "sort-close:"
    func isPending(_ workspace: String?) -> Bool { workspace?.hasPrefix(Self.pendingPrefix) == true }

    @discardableResult
    func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) -> WorkspaceReconciliation {
        let timing = TilingTiming("reconcile", windows: present.count)
        defer { timing.finish() }
        let held = movingToSpace || NSEvent.pressedMouseButtons & 1 != 0
        let observation = WorkspaceObservation(
            displays: screens.map {
                .init(id: $0.uuid, frame: $0.frame, space: Spaces.current(display: $0.uuid),
                      spaces: Set(Spaces.list(display: $0.uuid)?.ids ?? []))
            },
            frames: windows.mapValues(\.cachedFrame), present: present,
            held: held ? present : workspaceMoves.union(present.filter { animator.isBusy($0) }),
            fullscreen: fullscreenSpaces())
        let plan = WorkspaceReconciliation.reconcile(observation, model: model, virtual: config.virtualWorkspaces,
                                                     homeSpace: homeSpace, displayOf: displayOf)
        model = plan.model
        homeSpace = plan.homeSpace
        displayOf = plan.displayOf
        return plan
    }

    func fullscreenSpaces() -> [CGWindowID: UInt64] {
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

    func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        for screen in Screen.all() {
            homeSpace[screen.uuid] = Spaces.current(display: screen.uuid)
            if !isVirtual(virtualShown[screen.uuid]) { virtualShown[screen.uuid] = nil }
        }
        model.keepWorkspaces(where: isVirtual)
        refresh()
        HUD.shared.show("Ouch workspaces live on this Desktop", on: currentScreen()?.nsScreen)
    }

    var homeSpaceSummary: String {
        guard config.virtualWorkspaces else { return "" }
        let names = Screen.all().compactMap { screen -> String? in
            guard let home = homeSpace[screen.uuid], let info = Spaces.list(display: screen.uuid),
                  let i = info.ids.firstIndex(of: home),
                  let desktop = info.desktops.firstIndex(of: i) else { return nil }
            return "Desktop \(desktop + 1)" + (Screen.all().count > 1 ? " on \(screen.nsScreen.localizedName)" : "")
        }
        return names.joined(separator: ", ")
    }
}
