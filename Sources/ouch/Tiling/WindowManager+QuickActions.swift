import AppKit

extension WindowManager {

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
            QuickAction(id: actionID, title: title, symbol: symbol, key: quickActionKey(dispatcher, arg, mode: mode),
                        isOn: isOn, destructive: destructive) { [weak self] in
                self?.runQuickAction(actionID, on: id) { $0.dispatch(dispatcher, arg) }
            }
        }

        var out = [action("float", w.isFloating ? "Tile" : "Float", "macwindow.on.rectangle", "togglefloating", isOn: w.isFloating)]
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
        out.append(QuickAction(id: "minimize", title: "Minimize", symbol: "minus.square") { [weak self] in
            self?.runQuickAction("minimize", on: id) { wm in wm.windows[id]?.element.set(kAXMinimizedAttribute, kCFBooleanTrue) }
        })
        out.append(action("close", "Close", "xmark.square", "killactive", destructive: true))
        return (quickActionTitle(w), out)
    }

    private func quickActionWindow(at point: CGPoint) -> Window? {
        let h = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: point.x, y: h - point.y)
        guard let hit = CGWindowInfo.normalWindow(at: p), visible.contains(hit.id), let w = windows[hit.id] else { return nil }
        return w
    }

    private func quickActionTitle(_ w: Window) -> String {
        let title = w.element.string(kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = title.isEmpty ? (NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "Window") : title
        return name.count > 28 ? name.prefix(27).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    private func runQuickAction(_ name: String, on id: CGWindowID, _ body: @escaping (WindowManager) -> Void) {
        guard let w = windows[id], w.isValid else { Log.debug("quick action: \(name) skipped, window \(id) is gone"); return }
        Log.debug("quick action: \(name) on \(id) \(w.bundleID ?? "")")
        if focusedWindow()?.id != id { focus(w) }
        body(self)
    }


    private func quickActionMode() -> String {
        if !Hotkeys.shared.submap.isEmpty { return Hotkeys.shared.submap }
        return config.bindings.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.arg.lowercased() != "reset" }?.arg ?? ""
    }

    private func quickActionKey(_ dispatcher: String, _ arg: String, mode: String) -> String {
        guard !mode.isEmpty, let b = config.bindings.first(where: {
            $0.submap == mode && sameAction($0.dispatcher, $0.arg, dispatcher, arg)
        }) else { return "" }
        return KeyWords.caps(b, long: false).joined()
    }

    private func sameAction(_ d1: String, _ a1: String, _ d2: String, _ a2: String) -> Bool {
        let m1 = Actions.match(BindRow(mods: "", key: "", dispatcher: d1, args: a1))
        let m2 = Actions.match(BindRow(mods: "", key: "", dispatcher: d2, args: a2))
        if let m1, let m2 { return m1.dispatcher == m2.dispatcher && m1.args == m2.args }
        return d1.lowercased() == d2.lowercased() && a1.lowercased() == a2.lowercased()
    }

    private func nextWorkspaceDispatch(mode: String) -> (String, String) {
        let b = config.bindings.first {
            $0.submap == mode && ["movetoworkspace", "movetoworkspacesilent"].contains($0.dispatcher)
                && ["e+1", "+1", "r+1", "m+1"].contains($0.arg.lowercased())
        }
        return b.map { ($0.dispatcher, $0.arg) } ?? ("movetoworkspacesilent", "+1")
    }
}

private extension Layout {
    var hasMainPane: Bool {
        switch self {
        case .fullscreen, .column, .row, .floating: false
        default: true
        }
    }
}
