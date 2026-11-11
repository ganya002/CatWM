import AppKit
import CatWMKit
import QuartzCore

struct AppSurface: TilingSurface {
    private let fills = WindowResizeFills()
    private let liveBuffers = WindowLiveBuffers()

    func start(_ manager: WindowManager) {
        fills.excluded = { SplitHandle.shared.windowIDs }
        let landed = manager.animator.onLanded
        manager.animator.onLanded = { [weak fills, weak liveBuffers] in
            landed?()
            fills?.refresh?()
            liveBuffers?.refresh?()
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

    private func setResizeAnimation(_ mode: ResizeAnimation) {
        let manager = WindowManager.shared
        let animator = manager.animator
        let streaming = liveBuffers.refresh != nil
        if mode != .colorFill, animator.windowPresentation != nil {
            animator.windowPresentation = nil
            fills.refresh = nil
            fills.close()
            Log.info("window-fill: color-only tiling disabled")
        }
        if mode != .stream, streaming {
            liveBuffers.stop()
            animator.makeResizeScene = nil
            Log.info("live-window: native-size buffers disabled")
        }
        if mode != .snapshot, mode != .stream { animator.makeResizeScene = nil }
        switch mode {
        case .live:
            break
        case .colorFill:
            guard animator.windowPresentation == nil else { return }
            animator.windowPresentation = fills
            fills.refresh = { [weak manager, weak fills] in
                guard let manager else { return }
                fills?.warm(manager.windows) { [weak manager] in manager?.animator.isAnimating($0) ?? true }
            }
            fills.refresh?()
            Log.info("window-fill: color-only tiling enabled")
        case .snapshot:
            guard animator.makeResizeScene == nil else { return }
            startScenes(animator)
        case .stream:
            guard !streaming else { return }
            startStreams(manager)
            Log.info("live-window: native-size buffers enabled")
        }
    }

    private func startStreams(_ manager: WindowManager) {
        startScenes(manager.animator, live: liveBuffers)
        liveBuffers.refresh = { [weak manager, weak liveBuffers] in
            guard let manager, let liveBuffers, let order = WindowServerList.onScreen() else { return }
            let screens = Screen.all()
            let capacity = CGSize(width: screens.map(\.frame.width).max() ?? 1,
                                  height: screens.map(\.frame.height).max() ?? 1)
            let ids = Set(manager.windows.keys).intersection(order).filter {
                manager.windows[$0]?.isFloating == false
            }
            liveBuffers.warm(ids, capacity: capacity)
            if ids.allSatisfy({ !manager.animator.isAnimating($0) }) {
                let frames = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
                    WindowSceneCapture.currentFrame(id).map { (id, $0) }
                })
                liveBuffers.prepare(frames: frames, screens: screens, excluding: SplitHandle.shared.windowIDs)
            }
        }
        liveBuffers.refresh?()
    }

    private func startScenes(_ animator: Animator, live: WindowLiveBuffers? = nil) {
        animator.makeResizeScene = { moves in
            let screens = Screen.all()
            guard moves.allSatisfy({ move in
                screens.contains { $0.frame.contains(move.target) && $0.frame.contains(move.window.cachedFrame) }
            }) else { return nil }
            var frames = Dictionary(moves.map { ($0.window.id, $0.from ?? $0.window.cachedFrame) },
                                    uniquingKeysWith: { _, latest in latest })
            var prepared: WindowSceneCapture?
            if let live {
                guard let scene = live.capture(moving: frames) else {
                    Log.debug("window-scene: live buffers or background not ready")
                    return nil
                }
                prepared = scene.capture
                frames = scene.frames
            }
            let moving = Set(moves.map(\.window.id))
            let regions = moves.map { ($0.from ?? $0.window.cachedFrame).union($0.target) }
                + frames.filter { !moving.contains($0.key) }.map(\.value)
            let excluded = SplitHandle.shared.windowIDs
            guard WindowSceneCapture.canPresent(regions, participants: Set(frames.keys),
                                                excluding: excluded) else {
                Log.debug("window-scene: obstructed; excluding \(excluded)")
                return nil
            }
            if let prepared {
                Log.debug("window-scene: live native buffers \(moving.count) of \(frames.count)")
                return WindowResizeScene(capture: prepared, frames: frames, live: live)
            }
            let started = CACurrentMediaTime()
            guard let capture = WindowSceneCapture.take(frames: frames, screens: screens,
                                                      excluding: excluded) else { return nil }
            Log.debug(String(format: "window-scene: captured %d windows in %.1fms", frames.count,
                             (CACurrentMediaTime() - started) * 1000))
            return WindowResizeScene(capture: capture, frames: frames)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            Log.debug("window-scene: prewarm \(WindowSceneCapture.prepare())")
        }
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
        setResizeAnimation(config.resizeAnimation)
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
        liveBuffers.stop()
        Hotkeys.shared.stop()
        Notifications.shared.setEnabled(false)
        TabStrips.shared.update(instant: true)
    }

    func tilesDidChange(instant: Bool) {
        fills.refresh?()
        liveBuffers.refresh?()
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
