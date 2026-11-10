import AppKit
import CatWMKit
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
            if action.id == "template.save" { self?.beginTemplateSave(); return }
            self?.dismissMenu()
            DispatchQueue.main.async { action.run() }
        }
        model.onSave = { [weak self] in self?.saveTemplate() }
        model.onDelete = { [weak self] in self?.deleteTemplate($0) }
        model.onCancelSave = { [weak self] in self?.cancelTemplateSave() }
    }

    func modeChanged(_ name: String) {
        dismissMenu()
        if name.isEmpty || !enabled { hide() } else { show() }
    }

    func tapped() {
        guard enabled, !Hotkeys.shared.submap.isEmpty else { return }
        if model.open || opening { dismissMenu(); return }
        let point = NSEvent.mouseLocation
        guard let found = WindowManager.shared.quickActions() else {
            HUD.shared.show("Grant Accessibility access to use templates", on: nil)
            return
        }
        show()
        closeWork?.cancel()
        closeWork = nil
        model.title = found.title
        model.actions = found.actions
        model.hovered = nil
        model.keyboardHover = nil
        model.trackPointer = false
        resetPointerTracking()
        let menu = menuPanel ?? makeMenuPanel()
        menuPanel = menu
        place(menu: menu, at: point)
        menu.ignoresMouseEvents = false
        menu.makeKeyAndOrderFront(nil)
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
        if mods.isEmpty, [125, 126].contains(code), !model.actions.isEmpty {
            if !isRepeat {
                let current = model.actions.firstIndex { $0.id == model.hovered }
                let next = code == 125 ? (current.map { ($0 + 1) % model.actions.count } ?? 0)
                    : (current.map { ($0 + model.actions.count - 1) % model.actions.count } ?? model.actions.count - 1)
                DispatchQueue.main.async { [weak self] in
                    guard let self, model.actions.indices.contains(next) else { return }
                    model.hovered = model.actions[next].id
                    model.keyboardHover = model.actions[next].id
                }
            }
            return true
        }
        if mods.isEmpty, code == 36 {
            if !isRepeat, let action = model.actions.first(where: { $0.id == model.hovered }) ?? model.actions.first {
                DispatchQueue.main.async { [weak self] in self?.model.onPick?(action) }
            }
            return true
        }
        guard let action = model.actions.first(where: { $0.keyCode == code && $0.keyMods == mods }) else {
            return false
        }
        if !isRepeat { DispatchQueue.main.async { [weak self] in self?.model.onPick?(action) } }
        return true
    }

    func dismissMenu() {
        guard model.open || opening else { return }
        resetTemplateSave()
        opening = false
        model.open = false
        model.hovered = nil
        model.keyboardHover = nil
        model.trackPointer = false
        resetPointerTracking()
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
        Motion.fade(dot, to: out ? 0 : 1, duration: out ? 0.09 : 0.18)
    }

    func startMoveTap() {
        guard moveTap == nil else { return }
        let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: cursorMoveCallback,
                                          userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        moveTap = tap
        moveSource = src
    }

    func stopMoveTap() {
        if let tap = moveTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let src = moveSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        moveTap = nil
        moveSource = nil
    }

    func reenableMoveTap() {
        if let tap = moveTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}
