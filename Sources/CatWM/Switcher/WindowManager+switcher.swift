import AppKit
import CatWMKit

extension WindowManager {
    func switcherItems() -> [SwitcherItem] {
        let timing = TilingTiming("switcher", windows: windows.count)
        defer { timing.finish() }
        let apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
                              uniquingKeysWith: { first, _ in first })
        func item(_ id: CGWindowID, _ pid: pid_t, title: String, workspace: String) -> SwitcherItem? {
            guard pid != getpid(), let app = apps[pid], app.activationPolicy == .regular, !app.isHidden,
                  !(app.bundleIdentifier.map { Config.lists($0, in: config.switcherExclude) } ?? false)
            else { return nil }
            return SwitcherItem(id: id, pid: pid, app: app.localizedName ?? "", title: title, workspace: workspace)
        }
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var items = windows.values
            .filter { present.contains($0.id) && !$0.minimized }
            .sorted { (place[$0.id] ?? .max, $0.id) < (place[$1.id] ?? .max, $1.id) }
            .compactMap { item($0.id, $0.pid, title: $0.title ?? "", workspace: switcherWorkspace($0.id)) }
        timing.checkpoint("here")
        let listed = Set(items.map(\.id))
        items += windowsOnOtherSpaces().filter { !listed.contains($0.info.id) }.compactMap { window in
            item(window.info.id, window.info.pid, title: windows[window.info.id]?.title ?? "", workspace: window.space)
        }
        timing.checkpoint("elsewhere")
        let focused = focusedWindow()?.id
        let rank = Dictionary(focusOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func rankOf(_ item: SwitcherItem) -> Int { item.id == focused ? -1 : rank[item.id] ?? .max }
        return items.enumerated().sorted { (rankOf($0.element), $0.offset) < (rankOf($1.element), $1.offset) }
            .map(\.element)
    }

    private func windowsOnOtherSpaces() -> [(info: CGWindowInfo, space: String)] {
        let displays = backend.screens().compactMap { Spaces.list(display: $0.uuid) }
        let names = Self.spaceLabels(displays)
        let current = Set(displays.compactMap { display in display.current.map { display.ids[$0] } })
        let desktop = scanner.desktop
        let onScreen = Set(desktop.windows.map(\.id))
        return desktop.allWindows.compactMap { info in
            guard !onScreen.contains(info.id), info.bounds.width >= 100, info.bounds.height >= 60,
                  let spaces = desktop.spaces[info.id], spaces.count == 1, let space = spaces.first,
                  !current.contains(space),
                  let label = workspace(on: space).map(workspaceLabel) ?? names[space] else { return nil }
            return (info, label)
        }
    }

    static func spaceLabels(_ displays: [Spaces.DisplaySpaces]) -> [UInt64: String] {
        var labels: [UInt64: String] = [:]
        for display in displays {
            for (index, id) in display.ids.enumerated() where id != 0 {
                labels[id] = display.desktops.firstIndex(of: index).map { "Desktop \($0 + 1)" } ?? "Full Screen"
            }
        }
        return labels
    }

    private func switcherWorkspace(_ id: CGWindowID) -> String {
        guard config.virtualWorkspaces, let workspace = workspaceOf[id], isVirtual(workspace) else { return "" }
        return workspaceLabel(workspace)
    }

    private func workspaceLabel(_ workspace: String) -> String {
        let number = workspaceNumber(workspace)
        return labels[workspace].map { "\(number) · \($0)" } ?? number
    }

    private func workspace(on space: UInt64) -> String? {
        config.virtualWorkspaces ? desktops.nativeCatalog.entry(space: space)?.name : nil
    }

    func switchTo(_ item: SwitcherItem) {
        if let space = Spaces.of(window: item.id).first, let workspace = workspace(on: space),
           let display = desktops.nativeCatalog.entry(workspace)?.display,
           backend.currentSpace(display: display) != space {
            lastFocused[workspace] = item.id
            showWorkspace(workspace, focusing: windows[item.id])
            return
        }
        if let window = windows[item.id], visible.contains(item.id) {
            focus(window)
            return
        }
        noteFocus(item.id)
        if let window = windows[item.id], showMaximised(window) { return }
        if stepToSpace(of: item.id) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceSettle) {
                if !WindowServerFocus.focus(pid: item.pid, window: item.id) {
                    NSRunningApplication(processIdentifier: item.pid)?.activate()
                }
            }
            return
        }
        if let window = windows[item.id] {
            scanner.run(window.pid) { window.focus() }
        } else if !WindowServerFocus.focus(pid: item.pid, window: item.id) {
            NSRunningApplication(processIdentifier: item.pid)?.activate()
        }
    }

    private static let spaceSettle = 0.6

    private func stepToSpace(of id: CGWindowID) -> Bool {
        guard let space = Spaces.of(window: id).first else { return false }
        for screen in backend.screens() {
            guard let info = backend.spaceList(display: screen.uuid), let target = info.ids.firstIndex(of: space),
                  let cur = info.current, cur != target, let combo = backend.stepShortcut(right: target > cur)
            else { continue }
            for _ in 0..<abs(target - cur) { postKey(combo) }
            return true
        }
        return false
    }
}
