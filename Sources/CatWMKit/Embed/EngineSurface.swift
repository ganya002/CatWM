import AppKit

struct EngineSurface: TilingSurface {
    func start(_ manager: WindowManager) {
        Hotkeys.shared.handler = { [weak manager] binding in manager?.dispatch(binding.dispatcher, binding.arg) }
        Hotkeys.shared.onSubmapChange = { [weak manager] name in manager?.modeChanged(name) }
        if !Notifications.shared.hasSources { Notifications.shared.installBuiltIn() }
        Notifications.shared.setEnabled(manager.config.tabNotificationBadges)
        setKeyBinds(enabled: manager.config.features.contains(.keys))
    }

    func apply(_ config: Config) {
        Hotkeys.shared.setBindings(config.workspaceBindings)
        guard WindowManager.shared.isStarted else { return }
        Notifications.shared.setEnabled(config.tabNotificationBadges)
    }

    func stop() {
        Hotkeys.shared.stop()
        Notifications.shared.setEnabled(false)
    }

    func setKeyBinds(enabled: Bool) {
        guard enabled else { return Hotkeys.shared.stop() }
        guard WindowManager.shared.input.keys, !Hotkeys.shared.start() else { return }
        Log.info("start: could not create the keyboard event tap; the host needs Accessibility")
    }

    var inMode: Bool { !Hotkeys.shared.submap.isEmpty }
    func leaveMode() { Hotkeys.shared.setSubmap("") }
    var keybindsActive: Bool { Hotkeys.shared.isActive }
    var keysPaused: Bool { Hotkeys.shared.paused }

    func setKeyTap(enabled: Bool) {
        guard Hotkeys.shared.tap != nil else { return }
        if enabled { Hotkeys.shared.restart() } else { Hotkeys.shared.disable() }
    }

    func showHUD(_: String, layout _: Layout?, on _: NSScreen?) {}
    func warnHUD(_: String, on _: NSScreen?) {}
    func tilesDidChange(instant _: Bool) {}
    func splitSwapped(on _: String) {}
    func tabsDidChange(instant _: Bool) {}
    func batchTabChanges(_ changes: () -> Void) { changes() }
    func restackTabStrips() {}
    var revealedTabGroup: Int? { nil }
    func previewTabDrop(_: Window, at _: CGPoint) -> Bool { false }
    func endTabPreview(of _: CGWindowID) -> (group: Int, index: Int)? { nil }
    var showsTabDrop: Bool { false }
    func showTabDropHint(over _: CGRect, adding _: Window) {}
    func hideTabDropHint() {}
    func followTabStrip(_: Int, at _: CGVector, lowest _: CGFloat) {}
    func endTabStripFollow() {}
    var watchesTitles: Bool { Notifications.shared.enabled }
    func titleChanged(_ window: Window) { Notifications.shared.titleChanged(window) }
    func windowForgotten(_ id: CGWindowID) { Notifications.shared.forget(id) }
    func abandonOverview() {}
    func toggleOverview() {}
    func undoOverview() {}
    func refreshed(_: [Screen]) {}
    func openSwitcher(backward _: Bool) {}
    func focusChanged() {}
    func toggleFocusEffect(_: FocusEffect) {}
    var loginItem: (enabled: Bool, needsApproval: Bool) { (false, false) }
    func preview(_: String, _: String) -> Bool { false }
}
