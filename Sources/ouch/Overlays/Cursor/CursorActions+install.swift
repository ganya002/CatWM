import AppKit
import SwiftUI

extension CursorActions {
    func install() {
        Hotkeys.shared.onModifierTap = { [weak self] in self?.tapped() }
        Hotkeys.shared.onEscape = { [weak self] in
            guard let self, model.open else { return false }
            DispatchQueue.main.async { [weak self] in self?.dismissMenu() }
            return true
        }
        Hotkeys.shared.onMenuKey = { [weak self] code, flags, isRepeat in
            self?.menuKey(code, flags, isRepeat) ?? false
        }
        model.onPick = { [weak self] action in
            self?.dismissMenu()
            DispatchQueue.main.async { action.run() }
        }
    }

    func modeChanged(_ name: String) {
        dismissMenu()
        if name.isEmpty || !enabled { hide() } else { show() }
    }

    func tapped() {
        guard enabled, !Hotkeys.shared.submap.isEmpty else { return }
        if model.open || opening { dismissMenu(); return }
        let point = NSEvent.mouseLocation
        guard let found = WindowManager.shared.quickActions(at: point) else {
            HUD.shared.show("No window here", on: nil)
            return
        }
        show()
        closeWork?.cancel()
        closeWork = nil
        model.title = found.title
        model.actions = found.actions
        model.hovered = nil
        let menu = menuPanel ?? makeMenuPanel()
        menuPanel = menu
        place(menu: menu, at: point)
        menu.ignoresMouseEvents = false
        menu.orderFrontRegardless()
        fadeDot(out: true)
        opening = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            opening = false
            if shown, !Hotkeys.shared.submap.isEmpty { model.open = true } else { closeMenuPanel() }
        }
    }

    func menuKey(_ code: UInt16, _ flags: CGEventFlags, _ isRepeat: Bool) -> Bool {
        guard model.open else { return false }
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        guard let action = model.actions.first(where: { $0.keyCode == code && $0.keyMods == mods }) else { return false }
        if !isRepeat { DispatchQueue.main.async { [weak self] in self?.model.onPick?(action) } }
        return true
    }

    func dismissMenu() {
        guard model.open || opening else { return }
        opening = false
        model.open = false
        model.hovered = nil
        menuPanel?.ignoresMouseEvents = true
        let work = DispatchWorkItem { [weak self] in self?.closeMenuPanel() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func closeMenuPanel() {
        closeWork?.cancel()
        closeWork = nil
        menuPanel?.orderOut(nil)
        menuPanel?.ignoresMouseEvents = true
        guard shown else { return }
        placeDot(at: NSEvent.mouseLocation)
        fadeDot(out: false)
    }

    func show() {
        guard !shown else { return }
        shown = true
        model.modGlyph = Self.glyph(of: WindowManager.shared.config.mainMod)
        let dot = dotPanel ?? makeDotPanel()
        dotPanel = dot
        dot.alphaValue = 1
        placeDot(at: NSEvent.mouseLocation)
        dot.orderFrontRegardless()
        startMoveTap()
    }

    func hide() {
        stopMoveTap()
        guard shown else { return }
        shown = false
        closeMenuPanel()
        dotPanel?.orderOut(nil)
    }

    func fadeDot(out: Bool) {
        guard let dot = dotPanel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = out ? 0.09 : 0.18
            dot.animator().alphaValue = out ? 0 : 1
        }
    }

    func startMoveTap() {
        guard moveTap == nil else { return }
        let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: cursorMoveCallback, userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        moveTap = t
        moveSource = src
    }

    func stopMoveTap() {
        if let t = moveTap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let src = moveSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        moveTap = nil
        moveSource = nil
    }

    func reenableMoveTap() {
        if let t = moveTap { CGEvent.tapEnable(tap: t, enable: true) }
    }

}
