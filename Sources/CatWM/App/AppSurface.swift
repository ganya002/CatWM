import AppKit

struct AppSurface: TilingSurface {
    func start(_ manager: WindowManager) {
        Hotkeys.shared.onSubmapChange = { [weak manager] name in
            Log.debug("mode: \(name.isEmpty ? "reset" : name)")
            ModeFX.shared.setActive(!name.isEmpty)
            ModeCursor.shared.setActive(!name.isEmpty)
            KeyHelp.shared.modeChanged(name)
            CursorActions.shared.modeChanged(name)
            Tips.shared.modeChanged(name)
            manager?.modeChanged(name)
        }
        Hotkeys.shared.handler = { [weak manager] binding in manager?.dispatch(binding.dispatcher, binding.arg) }
        KeyHelp.shared.install()
        CursorActions.shared.install()
        Switcher.shared.install()
        startKeyTap()
        Notifications.shared.installBuiltIn()
        HUD.shared.prepare(text: manager.currentWorkspace ?? "1")
    }

    private func startKeyTap() {
        guard Instance.input.keys else { return Log.info("start: key binds off in a scoped instance (CATWM_KEYS=on)") }
        guard !Hotkeys.shared.start() else { return }
        Log.info("start: could not create the keyboard event tap")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard !Hotkeys.shared.isActive else { return }
            HUD.shared.show("Keybinds unavailable: grant Accessibility", on: nil)
        }
    }

    func apply(_ config: Config) {
        Hotkeys.shared.setBindings(config.workspaceBindings)
        ModeFX.shared.style = config.modeEffect
        MacKeyboard.shared.setting = config.keyboardFinish
        Notifications.shared.setEnabled(config.tabNotificationBadges)
    }

    func showHUD(_ text: String, on screen: NSScreen?) { HUD.shared.show(text, on: screen) }

    func warnHUD(_ text: String, on screen: NSScreen?) { HUD.shared.warn(text, on: screen) }

    var inMode: Bool { !Hotkeys.shared.submap.isEmpty }
    func leaveMode() { Hotkeys.shared.setSubmap("") }
    var keybindsActive: Bool { Hotkeys.shared.isActive }
    var keysPaused: Bool { Hotkeys.shared.paused }

    func setKeyTap(enabled: Bool) {
        if enabled { Hotkeys.shared.restart() } else { Hotkeys.shared.disable() }
    }

    func tilesDidChange(instant: Bool) {
        TabStrips.shared.update(instant: instant)
    }

    func tabsDidChange(instant: Bool) { TabStrips.shared.update(instant: instant) }
    func batchTabChanges(_ changes: () -> Void) { TabStrips.shared.batch(changes) }
    func restackTabStrips() { TabStrips.shared.restack() }
    var revealedTabGroup: Int? { TabStripReveal.shared.revealed }
    func previewTabDrop(_ window: Window, at point: CGPoint) -> Bool { TabStrips.shared.preview(window, at: point) }
    func endTabPreview(of id: CGWindowID) -> (group: Int, index: Int)? { TabStrips.shared.endPreview(of: id) }
    var showsTabDrop: Bool { TabDropHint.shared.showing || TabStrips.shared.isPreviewing }

    func showTabDropHint(over rect: CGRect, adding window: Window) {
        TabDropHint.shared.show(over: rect, adding: window)
    }

    func hideTabDropHint() { TabDropHint.shared.hide() }

    func followTabStrip(_ group: Int, at offset: CGVector, lowest: CGFloat) {
        TabStripFollow.shared.follow(group, at: offset, lowest: lowest)
    }

    func endTabStripFollow() { TabStripFollow.shared.end() }

    var watchesTitles: Bool { Notifications.shared.enabled }
    func titleChanged(_ window: Window) { Notifications.shared.titleChanged(window) }
    func windowForgotten(_ id: CGWindowID) { Notifications.shared.forget(id) }

    func abandonOverview() { SortPanel.shared.abandon() }
}
