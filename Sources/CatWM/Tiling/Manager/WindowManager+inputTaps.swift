import AppKit

extension WindowManager {
    func startKeyboardTap() {
        guard !Hotkeys.shared.start() else { return }
        Log.info("start: could not create the keyboard event tap")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard !Hotkeys.shared.isActive else { return }
            HUD.shared.show("Keybinds unavailable: grant Accessibility", on: nil)
        }
    }

    func startMouseTaps(logFailure: Bool = false) {
        nativeGestures.start()
        guard !dockWindowPull.isInstalled else { return }
        if dockWindowPull.start() {
            dockArea.refresh()
        } else if logFailure {
            Log.info("Dock window import: mouse event tap unavailable")
        }
    }

    func setInputTaps(enabled: Bool) {
        if enabled { Hotkeys.shared.restart() } else { Hotkeys.shared.disable() }
        dockWindowPull.setEnabled(enabled)
        nativeGestures.setEnabled(enabled)
        Log.info("input taps \(enabled ? "on" : "off")")
    }
}
