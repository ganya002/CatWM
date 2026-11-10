import AppKit
import CatWMKit
import SwiftUI

final class MenuBarTip {
    private struct Placement {
        let state: MenuBarTipModel.State
        let anchor: NSRect?
        let screen: NSScreen?
    }

    static let shared = MenuBarTip()

    weak var statusButton: NSStatusBarButton?
    var suppressed = false { didSet { if suppressed != oldValue { update() } } }

    private let glide = PanelGlide()
    private var panel: CatWMPanel?
    private var host: NSHostingView<MenuBarTipView>?
    private let model = MenuBarTipModel()
    private var timer: Timer?
    private var shown = false
    private var goodSince: Date?

    func show() {
        guard timer == nil else { return }
        if panel == nil {
            let hosting = NSHostingView(rootView: MenuBarTipView(model: model))
            let tipPanel = CatWMPanel(role: .overlay(.floating, clickThrough: true))
            tipPanel.contentView = hosting
            tipPanel.alphaValue = 0
            panel = tipPanel
            host = hosting
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
        let placement = locate()
        let state = placement.state, anchor = placement.anchor, screen = placement.screen
        if model.state != state { withAnimation(Motion.fadeSlow) { model.state = state } }
        if state == .good { goodSince = goodSince ?? Date() } else { goodSince = nil }
        let settled = goodSince.map { Date().timeIntervalSince($0) > 3 } ?? false
        guard let screen, !suppressed, !settled, timer != nil else { return setVisible(false) }
        let size = host.fittingSize
        let top = screen.visibleFrame.maxY - 4 + (MenuBarTipView.inset.top - 10)
        var x = (anchor?.midX ?? screen.frame.maxX - 40) - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let caret = anchor.map { min(max($0.midX - x, 30), size.width - 30) }
        if model.caret != caret { model.caret = caret }
        let frame = CatWMPanel.frame(size: size, on: screen, anchor: .origin(NSPoint(x: x, y: top - size.height)),
                                    inset: MenuBarTipView.inset).integral
        if panel.frame != frame {
            if shown && abs(panel.frame.minX - frame.minX) > 1 {
                var spec = MotionSpec(WindowManager.shared.config)
                spec.duration = 0.3
                glide.to(frame, on: panel, spec: spec)
            } else {
                glide.stop()
                panel.setFrame(frame, display: true)
            }
        }
        setVisible(true)
    }

    private func setVisible(_ visible: Bool) {
        guard let panel, visible != shown else { return }
        shown = visible
        if visible {
            panel.orderFrontRegardless()
            Motion.group(0.35) { Motion.setAlpha(1, on: panel) }
        } else {
            Motion.group(0.2, changes: { Motion.setAlpha(0, on: panel) }, completion: { [weak self] in
                if self?.shown == false { panel.orderOut(nil) }
            })
        }
    }

    private func locate() -> Placement {
        let focused = CatWMPanel.pointerScreen()
        guard let window = statusButton?.window, window.occlusionState.contains(.visible),
              let itemScreen = NSScreen.screens.first(where: {
                  $0.frame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY))
              })
        else { return Placement(state: .hidden, anchor: nil, screen: focused) }
        let frame = window.frame
        let state = state(for: frame, on: itemScreen)
        if let focused, focused != itemScreen {
            return Placement(state: state, anchor: nil, screen: focused)
        }
        return Placement(state: state, anchor: frame, screen: itemScreen)
    }

    private func state(for frame: NSRect, on screen: NSScreen) -> MenuBarTipModel.State {
        if let (left, right) = screen.notchSides {
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
