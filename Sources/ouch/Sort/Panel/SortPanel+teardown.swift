import AppKit
import SwiftUI

extension SortPanel {
    func teardown() {
        dismiss.stop()
        pruneTimer?.invalidate()
        pruneTimer = nil
        guard active else { return }
        active = false
        Hotkeys.shared.paused = wasPaused
        model.end()
    }

    func close() {
        teardown()
        guard let panel, panel.isVisible else { return }
        panel.delegate = nil
        generation += 1
        let gen = generation
        let done = { [weak self] in
            guard let self, gen == generation else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            panel.alphaValue = 1
            host = nil
        }
        model.shown = false
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + model.motion.outDuration + 0.02, execute: done)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard active else { return }
        if Date() < applyingUntil {
            DispatchQueue.main.async { [weak self] in
                guard let self, active, let panel else { return }
                panel.makeKey()
            }
            return
        }
        finish()
    }

    func key(_ e: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        if panel.firstResponder is NSTextView {
            guard [53, 36, 76].contains(e.keyCode) else { return false }
            panel.makeFirstResponder(nil)
            return true
        }
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        var mods: CGEventFlags = []
        if flags.contains(.command) { mods.insert(.maskCommand) }
        if flags.contains(.option) { mods.insert(.maskAlternate) }
        if flags.contains(.control) { mods.insert(.maskControl) }
        if flags.contains(.shift) { mods.insert(.maskShift) }
        if wm.config.bindings.contains(where: { $0.dispatcher == "sort" && $0.submap.isEmpty && $0.keyCode == e.keyCode && $0.mods == mods }) {
            finish()
            return true
        }
        if flags == .command {
            if e.keyCode == 6 { model.undoRemove() }
            return e.keyCode == 6
        }
        switch e.keyCode {
        case 53: revert(); return true
        case 36, 76: if flags.isEmpty { finish(focus: true); return true }
        default: break
        }
        return model.handle(code: e.keyCode, mods: mods, characters: e.characters ?? "")
    }

    func undoApplied() {
        guard wm.undoSort() else { return }
        let screen = toast?.screen
        dismissToast()
        HUD.shared.show("Sort undone", on: screen)
    }

    func showToast(_ text: String, on screen: NSScreen?) {
        guard let screen else { return }
        dismissToast()
        let view = SortToastView(text: text, keys: ShortcutIndex().keys("sort-undo")) { [weak self] in self?.undoApplied() }
        let host = OuchHostingView(rootView: view)
        let p = OuchPanel(role: .overlay(.statusBar, clickThrough: false),
                          frame: OuchPanel.frame(size: host.fittingSize, on: screen, anchor: .bottom(24 - SortToastView.inset.bottom),
                                                 inset: SortToastView.inset))
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.28) { p.animator().alphaValue = 1 }
        toast = p
        let work = DispatchWorkItem { [weak self] in self?.dismissToast() }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dismissToast() {
        toastWork?.cancel()
        toastWork = nil
        guard let p = toast else { return }
        toast = nil
        wm.dropSortSnapshot()
        animate(0.2, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
}
