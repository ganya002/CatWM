import AppKit

extension WindowManager {
    func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let defaults = UserDefaults.standard
        nativeCatalog.saved = (defaults.dictionary(forKey: "ws.nativeSpaces") ?? [:]).compactMapValues {
            $0 as? UInt64
        }
        nativeCatalog.homes = defaults.dictionary(forKey: "ws.nativeDisplays") as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: "ws.windows") as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { savedWorkspaceOf[id] = value }
        }
        for (key, value) in defaults.dictionary(forKey: "ws.owners") as? [String: String] ?? [:] {
            if let id = CGWindowID(key) { savedOwnerOf[id] = value }
        }
        monitorOf = defaults.dictionary(forKey: "ws.monitors") as? [String: String] ?? [:]
        labels = defaults.dictionary(forKey: "ws.labels") as? [String: String] ?? [:]
        virtualShown = defaults.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (key, value) in defaults.dictionary(forKey: "ws.home") ?? [:] {
            if let space = value as? UInt64 { homeSpace[key] = space }
        }
        for (key, value) in defaults.dictionary(forKey: "ws.floating") as? [String: Bool] ?? [:] {
            if let id = CGWindowID(key) { savedFloating[id] = value }
        }
        loadNativeMigration(defaults)
        loadWorkspaceLayouts(defaults)
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    private func loadWorkspaceLayouts(_ defaults: UserDefaults) {
        let saved = defaults.dictionary(forKey: "ws.layouts") as? [String: String] ?? [:]
        for (workspace, value) in saved where isVirtual(workspace) {
            let parts = value.split(separator: " ").map(String.init)
            guard let layout = parts.first.flatMap(Layout.init(rawValue:)) else { continue }
            let screenState = state(workspace: workspace)
            screenState.layout = layout
            if parts.count > 1, let ratio = Double(parts[1]) {
                screenState.ratio = min(0.9, max(0.1, CGFloat(ratio)))
            }
            if parts.count > 2, let mainCount = Int(parts[2]) {
                screenState.mainCount = max(1, min(10, mainCount))
            }
        }
    }

    func owner(_ window: Window) -> String { "\(window.pid) \(window.bundleID ?? "")" }

    func saveWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let windowsMap = Dictionary(
            workspaceOf
                .filter { windows[$0.key] != nil && isVirtual($0.value) && !isPending($0.value) }
                .map { (String($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first })
        let monitors = monitorOf.filter { isVirtual($0.key) && !isPending($0.key) }
        let floating = Dictionary(
            windowsMap.keys.compactMap { key -> (String, Bool)? in
                guard let window = CGWindowID(key).flatMap({ windows[$0] }),
                      case .chosen(let floating) = window.userFloating else { return nil }
                return (key, floating)
            },
            uniquingKeysWith: { first, _ in first })
        let layouts = Dictionary(
            states.filter { isVirtual($0.key) && !isPending($0.key) }
                .map { ($0.key, "\($0.value.layout.rawValue) \($0.value.ratio) \($0.value.mainCount)") },
            uniquingKeysWith: { first, _ in first })
        let key = [
            "\(windowsMap.sorted { $0.key < $1.key })",
            "\(monitors.sorted { $0.key < $1.key })",
            "\(virtualShown.sorted { $0.key < $1.key })",
            "\(homeSpace.sorted { $0.key < $1.key })",
            "\(labels.sorted { $0.key < $1.key })",
            "\(floating.sorted { $0.key < $1.key })",
            "\(layouts.sorted { $0.key < $1.key })"
        ].joined(separator: "|")
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let defaults = UserDefaults.standard
        defaults.set(windowsMap, forKey: "ws.windows")
        let owners = Dictionary(
            windowsMap.keys.compactMap { key in
                CGWindowID(key).flatMap { windows[$0] }.map { (key, owner($0)) }
            },
            uniquingKeysWith: { first, _ in first })
        defaults.set(owners, forKey: "ws.owners")
        defaults.set(monitors, forKey: "ws.monitors")
        defaults.set(virtualShown, forKey: "ws.shown")
        defaults.set(homeSpace, forKey: "ws.home")
        defaults.set(labels, forKey: "ws.labels")
        defaults.set(floating, forKey: "ws.floating")
        defaults.set(layouts, forKey: "ws.layouts")
    }

    func showWorkspace(
        _ workspace: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true
    ) {
        guard config.virtualWorkspaces else { return }
        showNativeWorkspace(workspace, focusing: preferred, focus: takesFocus, quiet: quietWorkspaceHUD)
    }

    func showWorkspaceHUD(_ workspace: String, on monitor: Screen) {
        let number = workspaceNumber(workspace)
        let text = labels[workspace].map { "\(number) · \($0)" } ?? number
        let layout = state(workspace: workspace).layout
        DispatchQueue.main.async { [weak self] in
            guard self?.shown[monitor.uuid] == workspace else { return }
            HUD.shared.show(text, layout: layout, on: monitor.nsScreen)
        }
    }

    func focusShownWorkspace(_ workspace: String, preferred: Window?, on screen: Screen) {
        let candidates = [preferred?.id, lastFocused[workspace]].compactMap(\.self) + order
        if let id = candidates.first(where: { id in
            workspaceOf[id] == workspace && windows[id].map { window in
                !window.minimized && NSRunningApplication(processIdentifier: window.pid)?.isHidden != true
            } == true
        }), let window = windows[id] {
            focus(window, warp: !screen.frame.contains(mouseLocation()))
        } else {
            parkFocus(on: screen)
        }
    }

    func moveFocusedWindow(to workspace: String, follow: Bool) {
        guard let window = focusedWindow(), workspaceOf[window.id] != workspace else { return }
        moveWindow(window, toWorkspace: workspace, follow: follow)
    }
}
