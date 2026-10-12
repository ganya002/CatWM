import AppKit
import SwiftUI

/// A small hint that hangs under Ouch's menu bar item for the whole onboarding, suggesting it lives
/// near the right end of the menu bar. On a notched display, items that don't fit left of the
/// clock vanish behind the notch, and the ones furthest left go first. It follows the item while
/// the user drags it and turns into a quiet check once the spot is good. Clicks pass through.
final class MenuBarTip {
    static let shared = MenuBarTip()

    weak var statusButton: NSStatusBarButton?
    /// The tour's own card points at the menu bar on some steps; the tip steps aside for those.
    var suppressed = false { didSet { if suppressed != oldValue { update() } } }

    private var panel: OverlayPanel?
    private var host: NSHostingView<MenuBarTipView>?
    private let model = MenuBarTipModel()
    private var timer: Timer?
    private var shown = false

    func show() {
        guard timer == nil else { return }
        if panel == nil {
            let h = NSHostingView(rootView: MenuBarTipView(model: model))
            let p = OverlayPanel(frame: .zero, level: .floating, clickThrough: true)
            p.contentView = h
            p.alphaValue = 0
            panel = p
            host = h
        }
        // Often enough to keep up with the item while it's being dragged.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
        update()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        setVisible(false)
    }

    private func update() {
        guard let panel, let host else { return }
        let (state, anchor, screen) = locate()
        if model.state != state { withAnimation(.easeOut(duration: 0.25)) { model.state = state } }
        guard let screen, !suppressed, timer != nil else { return setVisible(false) }
        let size = host.fittingSize
        let top = screen.visibleFrame.maxY - 4
        var x = (anchor?.midX ?? screen.frame.maxX - 40) - size.width / 2
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let caret = anchor.map { min(max($0.midX - x, 30), size.width - 30) } // clear of the rounded corners
        if model.caret != caret { model.caret = caret }
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height).integral
        if panel.frame != frame {
            if shown && abs(panel.frame.minX - frame.minX) > 1 {
                animate(0.3) { panel.animator().setFrame(frame, display: true) }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
        setVisible(true)
    }

    private func setVisible(_ on: Bool) {
        guard let panel, on != shown else { return }
        shown = on
        if on {
            panel.orderFrontRegardless()
            animate(0.35) { panel.animator().alphaValue = 1 }
        } else {
            animate(0.2, changes: { panel.animator().alphaValue = 0 }) { [weak self] in
                if self?.shown == false { panel.orderOut(nil) }
            }
        }
    }

    /// Where the item is and whether that's a good spot. A hidden item has no anchor; the tip then
    /// sits at the right end of the menu bar of the screen with the pointer.
    private func locate() -> (MenuBarTipModel.State, NSRect?, NSScreen?) {
        let fallback = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let w = statusButton?.window, w.occlusionState.contains(.visible),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: w.frame.midX, y: w.frame.midY)) })
        else { return (.hidden, nil, fallback) }
        let f = w.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            if f.maxX > left.maxX && f.minX < right.minX { return (.hidden, nil, screen) } // under the notch
            // Left of the notch, or the first in line to be pushed under it when more items appear.
            let good = f.minX >= right.minX + right.width * 0.25
            return (good ? .good : .move, f, screen)
        }
        return (f.midX > screen.frame.midX ? .good : .move, f, screen)
    }
}

final class MenuBarTipModel: ObservableObject {
    enum State { case move, good, hidden }
    @Published var state = State.move
    @Published var caret: CGFloat? // x of the caret in the tip, nil when there's nothing to point at
}
