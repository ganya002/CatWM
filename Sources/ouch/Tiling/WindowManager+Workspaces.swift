// Tiling: Ouch virtual workspaces: names, lookup, sync with displays and the home Space.
import AppKit

extension WindowManager {
    // MARK: - Ouch workspaces

    func isShown(_ ws: String?) -> Bool { ws.map { Set(shown.values).contains($0) } ?? false }

    /// Workspaces sort numerically first ("2" before "10"), then by name.
    func workspaceSort(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    var currentWorkspace: String? { currentScreen().flatMap { virtualShown[$0.uuid] } }

    /// Workspaces with windows or on screen, for the menu bar indicator.
    func workspaceSummary() -> (current: String?, all: [(name: String, windows: Int, shown: Bool)]) {
        guard config.virtualWorkspaces, isStarted else { return (nil, []) }
        var counts: [String: Int] = [:]
        for (id, ws) in workspaceOf where windows[id] != nil && isVirtual(ws) && !isPending(ws) { counts[ws, default: 0] += 1 }
        let names = Set(counts.keys).union(virtualShown.values).sorted(by: workspaceSort)
        let showing = Set(virtualShown.values)
        let current = currentScreen().flatMap { virtualShown[$0.uuid] }
        return (current, names.map { ($0, counts[$0] ?? 0, showing.contains($0)) })
    }

    /// What the menu bar shows for the focused display: its workspace (or macOS desktop number),
    /// layout, and the apps on it in tiling order (floating ones last).
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

    /// `3`, `name:web`, `previous`, `+1`/`-1` (by number), `e+1`/`e-1` (next/previous with windows).
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

    /// Keeps workspace bookkeeping consistent with the displays that exist. In macOS-Spaces mode,
    /// mirrors whatever Space each display is showing.
    func isVirtual(_ ws: String?) -> Bool { ws.map { !$0.hasPrefix("space:") } ?? false }

    /// While the Sort panel is open, windows put in Close wait on a workspace of their own per display, which
    /// is never shown (so the usual parking hides them), never listed and never saved.
    static let pendingPrefix = "sort-close:"
    func isPending(_ ws: String?) -> Bool { ws?.hasPrefix(Self.pendingPrefix) == true }

    /// Keeps workspace bookkeeping consistent with the displays that exist.
    ///
    /// Ouch workspaces live on one "home" macOS Space per display. On any other Space a
    /// display behaves like macOS-Spaces mode: that Space is its workspace and nothing is parked,
    /// so having several macOS Spaces can't scramble anything.
    func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) {
        let uuids = Set(screens.map(\.uuid))
        for u in shown.keys where !uuids.contains(u) { shown[u] = nil }
        for u in virtualShown.keys where !uuids.contains(u) { virtualShown[u] = nil }
        if config.virtualWorkspaces {
            // A display that went away hands its workspaces to the first remaining one, like Hyprland.
            for (ws, m) in monitorOf where isVirtual(ws) && !uuids.contains(m) { monitorOf[ws] = screens[0].uuid }
        }
        var onHome = Set<String>()
        for s in screens {
            let space = Spaces.current(display: s.uuid)
            if config.virtualWorkspaces {
                if let home = homeSpace[s.uuid], let ids = Spaces.list(display: s.uuid)?.ids, !ids.isEmpty, !ids.contains(home) {
                    homeSpace[s.uuid] = nil // that Space was removed
                }
                if homeSpace[s.uuid] == nil { homeSpace[s.uuid] = space }
            }
            if config.virtualWorkspaces && space == homeSpace[s.uuid] {
                if virtualShown[s.uuid] == nil {
                    let own = monitorOf.filter { $0.value == s.uuid && isVirtual($0.key) && !isPending($0.key) && !virtualShown.values.contains($0.key) }
                        .map(\.key).sorted(by: workspaceSort).first
                    virtualShown[s.uuid] = own ?? firstFreeWorkspace()
                }
                shown[s.uuid] = virtualShown[s.uuid]
                onHome.insert(s.uuid)
            } else {
                shown[s.uuid] = "space:\(s.uuid):\(space)"
            }
            monitorOf[shown[s.uuid]!] = s.uuid
        }
        // A window we can see but whose workspace isn't showing is either parked (a Ouch
        // workspace whose display is on its home Space) or has moved between macOS Spaces, in
        // which case it joins whatever is showing where it is now.
        for id in present where !isShown(workspaceOf[id]) {
            let ws = workspaceOf[id]
            if isVirtual(ws), let m = ws.flatMap({ monitorOf[$0] }), onHome.contains(m) { continue }
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            workspaceOf[id] = shown[s.uuid]
        }
        for id in present where workspaceOf[id] == nil {
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            workspaceOf[id] = shown[s.uuid]
        }
    }

    /// Makes the macOS Space each display is showing now the one Ouch workspaces live on.
    func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        for s in Screen.all() {
            homeSpace[s.uuid] = Spaces.current(display: s.uuid)
            if !isVirtual(virtualShown[s.uuid]) { virtualShown[s.uuid] = nil }
        }
        // Windows here join the workspace that's now showing instead of a per-Space one.
        workspaceOf = workspaceOf.filter { isVirtual($0.value) }
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
