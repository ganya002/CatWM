import AppKit
import CatWMKit
import QuartzCore

struct AppSurface: TilingSurface {
    func start(_ manager: WindowManager) {
        if ProcessInfo.processInfo.environment["CATWM_RESIZE_SCENE"] == "1" {
            manager.animator.makeResizeScene = { moves in
                let screens = Screen.all()
                guard moves.allSatisfy({ move in
                    screens.contains { $0.frame.contains(move.target) && $0.frame.contains(move.window.cachedFrame) }
                }) else { return nil }
                let frames = Dictionary(moves.map { ($0.window.id, $0.from ?? $0.window.cachedFrame) },
                                        uniquingKeysWith: { _, latest in latest })
                let regions = moves.map { ($0.from ?? $0.window.cachedFrame).union($0.target) }
                guard WindowSceneCapture.canPresent(regions, participants: Set(frames.keys)) else { return nil }
                let started = CACurrentMediaTime()
                guard let capture = WindowSceneCapture.take(frames: frames, screens: screens) else { return nil }
                Log.debug(String(format: "window-scene: captured %d windows in %.1fms", frames.count,
                                 (CACurrentMediaTime() - started) * 1000))
                return WindowResizeScene(capture: capture, frames: frames)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                Log.debug("window-scene: prewarm \(WindowSceneCapture.prepare())")
            }
        }
        Hotkeys.shared.onSubmapChange = { [weak manager] name in
            Log.debug("mode: \(name.isEmpty ? "reset" : name)")
            ModeFX.shared.setActive(!name.isEmpty)
            ModeCursor.shared.setActive(!name.isEmpty)
            Popup.shared.closeAll()
            KeyHelp.shared.modeChanged(name)
            CursorActions.shared.modeChanged(name)
            Tips.shared.modeChanged(name)
            manager?.modeChanged(name)
        }
        Hotkeys.shared.handler = { [weak manager] binding in manager?.dispatch(binding.dispatcher, binding.arg) }
        Hotkeys.shared.onWindowModeClick = { point in
            let popup = Popup.shared
            if popup.hitsMenu(at: point) { return false }
            let menus = popup.windowNumbers
            popup.closeAll()
            guard let hit = CGWindowInfo.normalWindow(at: point, ignoring: menus),
                  WindowManager.shared.windows[hit.id] != nil else { return false }
            DispatchQueue.main.async { WindowContextMenu.open(hit.id) }
            return true
        }
        manager.animator.beginRun = { kind in PerfMonitor.shared.begin(kind).map { run in { run.end(apps: $0) } } }
        KeyHelp.shared.install()
        CursorActions.shared.install()
        Switcher.shared.install()
        startKeyTap(manager)
        Notifications.shared.installBuiltIn()
        HUD.shared.prepare(text: manager.currentWorkspace ?? "1", layout: manager.config.layouts.first)
    }

    private var features: Set<Feature> { WindowManager.shared.config.features }

    private func startKeyTap(_ manager: WindowManager) {
        guard manager.input.keys else { return Log.info("start: key binds off in a scoped instance (CATWM_KEYS=on)") }
        guard manager.config.features.contains(.keys) else { return Log.info("start: key binds are off in the config") }
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
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
    }

    func showHUD(_ text: String, layout: Layout?, on screen: NSScreen?) {
        guard features.contains(.hud) else { return }
        HUD.shared.show(text, layout: layout, on: screen)
    }

    func warnHUD(_ text: String, on screen: NSScreen?) {
        guard features.contains(.hud) else { return }
        HUD.shared.warn(text, on: screen)
    }

    var inMode: Bool { !Hotkeys.shared.submap.isEmpty }
    func leaveMode() { Hotkeys.shared.setSubmap("") }
    var keybindsActive: Bool { Hotkeys.shared.isActive }
    var keysPaused: Bool { Hotkeys.shared.paused }

    func setKeyTap(enabled: Bool) {
        if enabled { Hotkeys.shared.restart() } else { Hotkeys.shared.disable() }
    }

    func setKeyBinds(enabled: Bool) {
        if enabled { startKeyTap(WindowManager.shared) } else { Hotkeys.shared.stop() }
    }

    func stop() {
        Hotkeys.shared.stop()
        Notifications.shared.setEnabled(false)
        TabStrips.shared.update(instant: true)
    }

    func tilesDidChange(instant: Bool) {
        SplitHandle.shared.update(instant: instant)
        TabStrips.shared.update(instant: instant)
    }

    func splitSwapped(on screen: String) { SplitHandle.shared.confirmSwap(on: screen) }
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
    func undoOverview() { SortPanel.shared.undoApplied() }
    func refreshed(_ screens: [Screen]) { WindowManager.shared.watchCrowding(screens) }
    func openSwitcher(backward: Bool) { if features.contains(.switcher) { Switcher.shared.open(backward: backward) } }
    func focusChanged() { FocusDim.shared.update() }
    var loginItem: (enabled: Bool, needsApproval: Bool) { (LoginItem.shared.isEnabled, LoginItem.shared.needsApproval) }

    func toggleOverview() {
        let manager = WindowManager.shared
        if manager.config.virtualWorkspaces {
            SortPanel.shared.toggle()
        } else {
            HUD.shared.show("Overview needs CatWM workspaces", on: manager.currentScreen()?.nsScreen)
        }
    }

    func toggleFocusEffect(_ effect: FocusEffect) {
        FocusDim.features.first { $0.effect.dispatcher == effect.dispatcher }?.run()
    }

    func preview(_ command: String, _ argument: String) -> Bool {
        let words = argument.split(separator: " ").map(String.init)
        switch command {
        case "modefx": ModeFX.shared.command(words)
        case "panelfx": PanelMotionDemo.shared.command(words)
        case "intro": Onboarding.shared.playIntro(IntroScore.Arrangement.named(argument) ?? .standard)
        case "introlab": IntroLab.shared.open()
        default: return false
        }
        return true
    }
}
