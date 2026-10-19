import AppKit

extension WindowManager {

    func isShown(_ ws: String?) -> Bool { model.isShown(ws) }

    func workspaceSort(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    var currentWorkspace: String? { currentScreen().flatMap { virtualShown[$0.uuid] } }

    func workspaceSummary() -> (current: String?, all: [(name: String, windows: Int, shown: Bool)]) {
        guard config.virtualWorkspaces, isStarted else { return (nil, []) }
        var counts: [String: Int] = [:]
        for (id, ws) in workspaceOf where windows[id] != nil && isVirtual(ws) && !isPending(ws) { counts[ws, default: 0] += 1 }
        let names = Set(counts.keys).union(virtualShown.values).sorted(by: workspaceSort)
        let showing = Set(virtualShown.values)
        let current = currentScreen().flatMap { virtualShown[$0.uuid] }
        return (current, names.map { ($0, counts[$0] ?? 0, showing.contains($0)) })
    }

    func menuBarState() -> (workspace: String?, layout: Layout, pids: [pid_t])? {
        guard isStarted, let s = currentScreen() else { return nil }
        let ws = shown[s.uuid]
        let workspace: String?
        if config.virtualWorkspaces {
            workspace = virtualShown[s.uuid]
        } else if let list = Spaces.list(display: s.uuid), let cur = list.current, let n = list.desktops.firstIndex(of: cur) {
            workspace = String(n + 1)
        } else {
            workspace = nil
        }
        let here = order.filter { workspaceOf[$0] == ws && present.contains($0) }.compactMap { windows[$0] }
        var seen = Set<pid_t>()
        let pids = (here.filter { !$0.isFloating } + here.filter(\.isFloating)).map(\.pid).filter { seen.insert($0).inserted }
        return (workspace, state(for: s).layout, pids)
    }

    func resolveWorkspace(_ raw: String) -> String? {
        let a = raw.trimmingCharacters(in: .whitespaces)
        let lower = a.lowercased()
        let cur = currentWorkspace ?? "1"
        if a.isEmpty { return nil }
        if lower == "previous" { return currentScreen().flatMap { previousWorkspace[$0.uuid] } }
        if lower.hasPrefix("name:") { return String(a.dropFirst(5)) }
        for prefix in ["r", "m", ""] where lower.hasPrefix(prefix + "+") || lower.hasPrefix(prefix + "-") {
            guard let d = Int(lower.dropFirst(prefix.count).replacingOccurrences(of: "+", with: "")) else { break }
            return String(max(1, (Int(cur) ?? 1) + d))
        }
        if lower.hasPrefix("e+") || lower.hasPrefix("e-"), let d = Int(lower.dropFirst(1).replacingOccurrences(of: "+", with: "")) {
            let occupied = Set(workspaceOf.values).union(virtualShown.values).filter { isVirtual($0) && !isPending($0) }.sorted(by: workspaceSort)
            guard !occupied.isEmpty else { return nil }
            let i = occupied.firstIndex(of: cur) ?? 0
            return occupied[((i + d) % occupied.count + occupied.count) % occupied.count]
        }
        return a
    }

    func isVirtual(_ ws: String?) -> Bool { ws.map { !$0.hasPrefix(Self.spacePrefix) } ?? false }

    static let spacePrefix = "space:"
    static func spaceWorkspace(display uuid: String, space: UInt64) -> String { "\(spacePrefix)\(uuid):\(space)" }

    static let pendingPrefix = "sort-close:"
    func isPending(_ ws: String?) -> Bool { ws?.hasPrefix(Self.pendingPrefix) == true }

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
        leavingFullscreen = leavingFullscreen.filter { stillFullscreen.contains($0.key) && Date().timeIntervalSince($0.value) < 3 }
        for scan in scanner.results.values {
            for id in scan.fullscreen where windows[id] != nil && !scan.minimized.contains(id) && leavingFullscreen[id] == nil {
                if let spaces = scanner.desktop.spaces[id], spaces.count == 1, let space = spaces.first { found[id] = space }
            }
        }
        return found
    }

    func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        for s in Screen.all() {
            homeSpace[s.uuid] = Spaces.current(display: s.uuid)
            if !isVirtual(virtualShown[s.uuid]) { virtualShown[s.uuid] = nil }
        }
        model.keepWorkspaces(where: isVirtual)
        refresh()
        HUD.shared.show("Ouch workspaces live on this Desktop", on: currentScreen()?.ns)
    }

    var homeSpaceSummary: String {
        guard config.virtualWorkspaces else { return "" }
        let names = Screen.all().compactMap { s -> String? in
            guard let home = homeSpace[s.uuid], let info = Spaces.list(display: s.uuid),
                  let i = info.ids.firstIndex(of: home), let d = info.desktops.firstIndex(of: i) else { return nil }
            return "Desktop \(d + 1)" + (Screen.all().count > 1 ? " on \(s.ns.localizedName)" : "")
        }
        return names.joined(separator: ", ")
    }
}
