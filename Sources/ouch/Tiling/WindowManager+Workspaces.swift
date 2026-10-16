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

    private func firstFreeWorkspace() -> String {
        let used = Set(workspaceOf.values).union(virtualShown.values).filter(isVirtual)
        var n = 1
        while used.contains(String(n)) { n += 1 }
        return String(n)
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

    func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) {
        let uuids = Set(screens.map(\.uuid))
        for u in shown.keys where !uuids.contains(u) { shown[u] = nil }
        for u in virtualShown.keys where !uuids.contains(u) { virtualShown[u] = nil }
        if config.virtualWorkspaces {
            for (ws, m) in monitorOf where isVirtual(ws) && !uuids.contains(m) { monitorOf[ws] = screens[0].uuid }
        }
        var onHome = Set<String>()
        for s in screens {
            let space = Spaces.current(display: s.uuid)
            if config.virtualWorkspaces {
                if let home = homeSpace[s.uuid], let ids = Spaces.list(display: s.uuid)?.ids, !ids.isEmpty, !ids.contains(home) {
                    homeSpace[s.uuid] = nil
                }
                if homeSpace[s.uuid] == nil { homeSpace[s.uuid] = space }
            }
            if config.virtualWorkspaces && space == homeSpace[s.uuid] {
                if virtualShown[s.uuid] == nil {
                    let own = monitorOf.filter { $0.value == s.uuid && isVirtual($0.key) && !isPending($0.key) && !virtualShown.values.contains($0.key) }
                        .map(\.key).sorted(by: workspaceSort).first
                    virtualShown[s.uuid] = own ?? firstFreeWorkspace()
                }
                model.show(virtualShown[s.uuid], on: s.uuid)
                onHome.insert(s.uuid)
            } else {
                model.show(Self.spaceWorkspace(display: s.uuid, space: space), on: s.uuid)
            }
            monitorOf[shown[s.uuid]!] = s.uuid
        }
        let held = movingToSpace || NSEvent.pressedMouseButtons & 1 != 0
        for id in present where !held && !workspaceMoves.contains(id) && !animator.isBusy(id) {
            guard let w = windows[id], let ws = workspaceOf[id], isShown(ws) else { continue }
            let f = w.frame
            guard !f.isNull, !isParked(f, screens), let now = screen(containing: f, in: screens)?.uuid else { continue }
            defer { displayOf[id] = now }
            guard let was = displayOf[id], was != now, uuids.contains(was),
                  let m = monitorOf[ws], m != now, let dest = shown[now] else { continue }
            Log.info("workspaces: window \(id) moved from \(was) to \(now) outside Ouch; it joins \(dest)")
            model.assign(id, to: dest)
        }
        for id in present where !isShown(workspaceOf[id]) {
            let ws = workspaceOf[id]
            if isVirtual(ws), let m = ws.flatMap({ monitorOf[$0] }), onHome.contains(m) { continue }
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            model.assign(id, to: shown[s.uuid])
        }
        for id in present where workspaceOf[id] == nil {
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            model.assign(id, to: shown[s.uuid])
        }
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
