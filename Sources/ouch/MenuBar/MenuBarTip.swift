import AppKit
import SwiftUI

final class MenuBarTip {
    static let shared = MenuBarTip()

    weak var statusButton: NSStatusBarButton?
    var suppressed = false { didSet { if suppressed != oldValue { update() } } }

    private var panel: OverlayPanel?
    private var host: NSHostingView<MenuBarTipView>?
    private let model = MenuBarTipModel()
    private var timer: Timer?
    private var shown = false
    private var goodSince: Date?

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
        timer?.tolerance = 0.05
        update()
    }

    func hide() {
        goodSince = nil
        timer?.invalidate()
        timer = nil
        setVisible(false)
    }

    private func update() {
        guard let panel, let host else { return }
        let (state, anchor, screen) = locate()
        if model.state != state { withAnimation(.easeOut(duration: 0.25)) { model.state = state } }
        if state == .good { goodSince = goodSince ?? Date() } else { goodSince = nil }
        let settled = goodSince.map { Date().timeIntervalSince($0) > 3 } ?? false
        guard let screen, !suppressed, !settled, timer != nil else { return setVisible(false) }
        let size = host.fittingSize
        let top = screen.visibleFrame.maxY - 4 + (MenuBarTipView.inset.top - 10)
        var x = (anchor?.midX ?? screen.frame.maxX - 40) - size.width / 2
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let caret = anchor.map { min(max($0.midX - x, 30), size.width - 30) }
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

    private func locate() -> (MenuBarTipModel.State, NSRect?, NSScreen?) {
        let focused = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let w = statusButton?.window, w.occlusionState.contains(.visible),
              let itemScreen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: w.frame.midX, y: w.frame.midY)) })
        else { return (.hidden, nil, focused) }
        let f = w.frame
        let state = state(for: f, on: itemScreen)
        if let focused, focused != itemScreen {
            return (state, nil, focused)
        }
        return (state, f, itemScreen)
    }

    private func state(for frame: NSRect, on screen: NSScreen) -> MenuBarTipModel.State {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            if frame.maxX > left.maxX && frame.minX < right.minX { return .hidden }
            return frame.minX >= right.minX + right.width * 0.25 ? .good : .move
        }
        return frame.midX > screen.frame.midX ? .good : .move
    }
}

final class MenuBarTipModel: ObservableObject {
    enum State { case move, good, hidden }
    @Published var state = State.move
    @Published var caret: CGFloat?
}
