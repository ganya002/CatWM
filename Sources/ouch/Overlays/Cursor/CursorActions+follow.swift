import AppKit
import SwiftUI

extension CursorActions {
    func follow(cgPoint: CGPoint) {
        guard shown, !model.open, !opening, menuPanel?.isVisible != true else { return }
        let p = CGPoint(x: cgPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - cgPoint.y)
        guard p != lastFollow else { return }
        lastFollow = p
        placeDot(at: p)
    }

    func placeDot(at point: CGPoint) {
        let side = Self.dotSize
        let o = CursorActionsView.markOffset
        dotPanel?.setFrameOrigin(CGPoint(x: (point.x + o.width - side / 2).rounded(), y: (point.y - o.height - side / 2).rounded()))
    }

    func place(menu panel: NSPanel, at point: CGPoint) {
        let m = CursorActionsView.margin, gap: CGFloat = 10
        let size = CursorActionsView.menuSize(for: model.actions)
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
        let host = OuchHostingView(rootView: CursorActionsView(model: model))
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    static func makePanel() -> NSPanel { OuchPanel(role: .pointer) }
}
