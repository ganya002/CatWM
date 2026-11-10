import AppKit
import CatWMKit
import SwiftUI

extension SortPanel {
    func teardown() {
        dismiss.stop()
        Popup.shared.closeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
        guard active else { return }
        active = false
        ghostPanel?.orderOut(nil)
        ghostPanel?.contentView = nil
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

    func windowDidResignKey(_: Notification) {
        guard active, !Popup.shared.isOpen else { return }
        if Date() < applyingUntil {
            DispatchQueue.main.async { [weak self] in
                guard let self, active, let panel else { return }
                panel.makeKey()
            }
            return
        }
        finish()
    }

    func key(_ event: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        if panel.firstResponder is NSTextView {
            guard [53, 36, 76].contains(event.keyCode) else { return false }
            panel.makeFirstResponder(nil)
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let mods = Self.eventFlags(flags)
        let isSortKey = manager.config.bindings.contains {
            $0.dispatcher == "sort" && $0.submap.isEmpty && $0.keyCode == event.keyCode && $0.mods == mods
        }
        if isSortKey {
            finish()
            return true
        }
        if flags == .command { return event.keyCode == 6 }
        switch event.keyCode {
        case 53: revert(); return true
        case 36, 76: if flags.isEmpty { finish(focus: true); return true }
        default: break
        }
        return model.handle(code: event.keyCode, mods: mods, characters: event.characters ?? "")
    }

    private static func eventFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var mods: CGEventFlags = []
        if flags.contains(.command) { mods.insert(.maskCommand) }
        if flags.contains(.option) { mods.insert(.maskAlternate) }
        if flags.contains(.control) { mods.insert(.maskControl) }
        if flags.contains(.shift) { mods.insert(.maskShift) }
        return mods
    }

    func undoApplied() {
        guard manager.undoSort() else { return }
        undoWork?.cancel()
        undoWork = nil
        HUD.shared.show("Overview changes undone", on: nil)
    }

    func keepUndo() {
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dropUndo() }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dropUndo() {
        undoWork?.cancel()
        undoWork = nil
        manager.dropSortSnapshot()
    }
}
