// Tiling: the cursor quick actions: what can be done to the window under the pointer, and how it's done.
import AppKit

extension WindowManager {
    // MARK: - Cursor quick actions

    /// The menu for the managed window under `point` (AppKit screen space, y up), or nil when there is none.
    /// Each action focuses that window first and then runs the dispatcher a key would, so nothing here tiles.
    func quickActions(at point: CGPoint) -> (title: String, actions: [QuickAction])? {
        guard isStarted, let w = quickActionWindow(at: point) else { return nil }
        let id = w.id
        let screens = Screen.all()
        let s = screen(of: w, in: screens)
        let st = s.map { state(for: $0) }
        let ids = s.map { tiled(on: $0) } ?? []
        let isTiled = !w.isFloating && ids.contains(id)
        let mode = quickActionMode()

        func action(_ actionID: String, _ title: String, _ symbol: String, _ dispatcher: String, _ arg: String = "",
                    isOn: Bool = false, destructive: Bool = false) -> QuickAction {
            let shortcut = quickActionShortcut(dispatcher, arg, mode: mode)
            return QuickAction(id: actionID, title: title, symbol: symbol, keys: shortcut?.keys ?? [],
                               keyCode: shortcut?.code, keyMods: shortcut?.mods ?? [],
                               isOn: isOn, destructive: destructive) { [weak self] in
                self?.runQuickAction(actionID, on: id) { $0.dispatch(dispatcher, arg) }
            }
        }

        var out = [action("float", w.isFloating ? "Tile" : "Float", "macwindow.on.rectangle", "togglefloating", isOn: w.isFloating)]
        // Zoom only covers tiles (a floating window keeps its own frame).
        if isTiled {
            out.append(action("zoom", "Zoom", "arrow.up.left.and.arrow.down.right", "fullscreen", isOn: st?.zoomed == id))
        }
        out.append(action("nativefullscreen", "Native Full Screen", "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
                          "nativefullscreen", isOn: w.isNativeFullscreen))
        if isTiled, let st, ids.count > 1, ids.first != id, st.layout.hasMainPane {
            out.append(action("main", "Make Main", "star.square", "layoutmsg", "swapwithmaster"))
        }
        if config.layouts.count > 1 {
            out.append(action("layout", "Next Layout", "rectangle.2.swap", "cyclelayout", "next"))
        }
        if screens.count > 1 {
            out.append(action("display", "Send to Next Display", "rectangle.portrait.and.arrow.right", "movewindowtomonitor", "+1"))
        }
        if config.virtualWorkspaces, isVirtual(workspaceOf[id]) {
            let (d, a) = nextWorkspaceDispatch(mode: mode)
            out.append(action("workspace", "Send to Next Workspace", "arrow.right.square", d, a))
        }
        out.append(action("minimize", "Minimize", "minus.square", "minimize"))
        out.append(action("close", "Close", "xmark.square", "killactive", destructive: true))
        return (quickActionTitle(w), out)
    }

    /// The topmost managed window under the point, found the way focus follows mouse finds it.
    private func quickActionWindow(at point: CGPoint) -> Window? {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: point.x, y: h - point.y) // AppKit (y up) → Quartz/AX (y down)
        guard let hit = CGWindowInfo.normalWindow(at: p), visible.contains(hit.id), let w = windows[hit.id] else { return nil }
        return w
    }

    /// The window's title, else its app's name, short enough for the menu's header.
    private func quickActionTitle(_ w: Window) -> String {
        let title = w.element.string(kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = title.isEmpty ? (NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "Window") : title
        return name.count > 28 ? name.prefix(27).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    /// Focuses the window, then runs the action on it. The dispatchers act on the focused window, and
    /// `focus(_:)` makes it the focused one at once (macOS reports it later), so this needs no wait.
    private func runQuickAction(_ name: String, on id: CGWindowID, _ body: @escaping (WindowManager) -> Void) {
        guard let w = windows[id], w.isValid else { Log.debug("quick action: \(name) skipped, window \(id) is gone"); return }
        Log.debug("quick action: \(name) on \(id) \(w.bundleID ?? "")")
        if focusedWindow()?.id != id { focus(w) }
        body(self)
    }

    // MARK: Key hints

    /// The mode the hints come from: the one that's on, else the one the global binds enter.
    private func quickActionMode() -> String {
        if !Hotkeys.shared.submap.isEmpty { return Hotkeys.shared.submap }
        return config.bindings.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.arg.lowercased() != "reset" }?.arg ?? ""
    }

    /// The window-mode shortcut bound to this dispatcher, as keycaps plus the key the menu matches.
    /// Aliases count (`movewindowtomonitor +1` is `movewindow mon:+1`), so a renamed bind still shows.
    /// Scroll and swipe binds are left out: the menu is driven from the keyboard.
    private func quickActionShortcut(_ dispatcher: String, _ arg: String, mode: String) -> (keys: [String], code: UInt16, mods: CGEventFlags)? {
        guard !mode.isEmpty, let b = config.bindings.first(where: {
            $0.submap == mode && $0.keyCode < 0x1000 && Actions.same($0.dispatcher, $0.arg, dispatcher, arg)
        }) else { return nil }
        let mods = b.mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return (KeyWords.caps(b, long: false), b.keyCode, mods)
    }

    /// The user's own "next workspace" move when window mode binds one (so the hint is its key),
    /// else a quiet move to the next workspace by number.
    private func nextWorkspaceDispatch(mode: String) -> (String, String) {
        let b = config.bindings.first {
            $0.submap == mode && Actions.isNextWorkspace($0.dispatcher, $0.arg)
        }
        return b.map { ($0.dispatcher, $0.arg) } ?? ("movetoworkspacesilent", "+1")
    }
}

private extension Layout {
    /// Layouts where the first tiles are a main pane, so swapping with it means something.
    var hasMainPane: Bool {
        switch self {
        case .fullscreen, .column, .row, .floating: false
        default: true
        }
    }
}
