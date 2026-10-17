import AppKit
import QuartzCore
import SwiftUI

extension CursorActions {
    func follow(cgPoint: CGPoint) {
        guard shown else { return }
        if model.open || opening || menuPanel?.isVisible == true {
            queuePointerNote()
            return
        }
        let raw = CGEvent(source: nil)?.location ?? cgPoint
        let p = CGPoint(x: raw.x, y: (NSScreen.screens.first?.frame.height ?? 0) - raw.y)
        guard p != lastFollow else { return }
        lastFollow = p
        placeDot(at: p)
    }

    func placeDot(at point: CGPoint) {
        guard let panel = dotPanel else { return }
        let side = Self.dotSize
        let o = CursorActionsView.markOffset
        let origin = CGPoint(x: (point.x + o.width - side / 2).rounded(), y: (point.y - o.height - side / 2).rounded())
        guard panel.frame.origin != origin else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrameOrigin(origin)
        CATransaction.commit()
        CATransaction.flush()
    }

    func place(menu panel: NSPanel, at point: CGPoint) {
        let m = CursorActionsView.margin, gap: CGFloat = 10
        let size = CursorActionsView.menuSize(for: model.actions, editing: model.templateDraft != nil)
        let screen = OuchPanel.screen(at: point)
        let v = screen.visibleFrame
        var x = point.x + gap, top = point.y - gap
        if x + size.width > v.maxX { x = point.x - gap - size.width }
        if top - size.height < v.minY { top = point.y + gap + size.height }
        let frame = OuchPanel.frame(size: CGSize(width: size.width + 2 * m, height: size.height + 2 * m), on: screen,
                                    anchor: .origin(NSPoint(x: (x - m).rounded(), y: (top - size.height - m).rounded())),
                                    inset: EdgeInsets(all: m))
        panel.setFrame(frame, display: true)
        model.anchor = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    func armPointerTracking() {
        pointerInRows = false
        pointerAnchor = NSEvent.mouseLocation
        notePointer(at: pointerAnchor)
    }

    func resetPointerTracking() {
        pointerInRows = false
        pointerAnchor = .zero
        pointerNoteQueued = false
    }

    func queuePointerNote() {
        guard model.open, model.trackPointer, !pointerNoteQueued else { return }
        pointerNoteQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pointerNoteQueued = false
            guard model.open, model.trackPointer else { return }
            notePointer(at: NSEvent.mouseLocation)
        }
    }

    func notePointer(at mouse: CGPoint) {
        guard model.open, model.trackPointer, let view = rowHover, let window = view.window, view.bounds.width > 1 else { return }
        let local = window.convertPoint(fromScreen: mouse)
        let origin = view.convert(CGPoint.zero, to: nil)
        let x = local.x - origin.x
        let y = origin.y - local.y
        let row = Self.rowUnder(view, at: local, x: x, y: y, actions: model.actions)
        let moved = abs(pointerAnchor.x - mouse.x) >= 1 || abs(pointerAnchor.y - mouse.y) >= 1
        if let row {
            guard moved || model.keyboardHover == nil else { return }
            pointerInRows = true
            if model.hovered != row { model.hovered = row }
            return
        }
        guard pointerInRows else { return }
        pointerInRows = false
        model.hovered = nil
    }

    static func rowUnder(_ view: NSView, at local: CGPoint, x: CGFloat, y: CGFloat, actions: [QuickAction]) -> String? {
        guard let clip = view.enclosingScrollView?.contentView, clip.bounds.contains(clip.convert(local, from: nil)) else { return nil }
        let top = view.convert(CGPoint.zero, to: nil).y - clip.convert(CGPoint(x: 0, y: clip.bounds.minY), to: nil).y
        let bottom = view.convert(CGPoint.zero, to: nil).y - clip.convert(CGPoint(x: 0, y: clip.bounds.maxY), to: nil).y
        let visible = min(top, bottom)..<max(top, bottom)
        return CursorActionsView.rowUnderPointer(x: x, y: y, width: view.bounds.width, actions: actions, visible: visible)
    }

    static func glyph(of flags: CGEventFlags) -> String {
        if flags.contains(.maskCommand) { return "⌘" }
        if flags.contains(.maskAlternate) { return "⌥" }
        if flags.contains(.maskControl) { return "⌃" }
        if flags.contains(.maskShift) { return "⇧" }
        return "⌥"
    }

    func makeDotPanel() -> NSPanel {
        let p = Self.makePanel()
        p.ignoresMouseEvents = true
        let host = NSHostingView(rootView: CursorMarkView(model: model))
        p.setContentSize(CGSize(width: Self.dotSize, height: Self.dotSize))
        p.contentView = host
        return p
    }

    func makeMenuPanel() -> NSPanel {
        let p = Self.makePanel()
        p.onClose = { [weak self] in
            guard let self else { return }
            if model.templateDraft != nil { cancelTemplateSave() } else { dismissMenu() }
        }
        let host = OuchHostingView(rootView: CursorActionsView(model: model))
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    static func makePanel() -> OuchPanel { OuchPanel(role: .pointer) }
}
