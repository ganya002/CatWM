import AppKit
import SwiftUI

extension Tips {
    func dismissSettings() {
        guard settings != nil else { return }
        withAnimation(Motion.easeOut) { settings = nil }
    }

    func showPanel(_ tip: Tip) -> Bool {
        let host = OuchHostingView(rootView: TipView(tip: tip, inset: TipView.panelInset))
        let size = host.fittingSize
        guard var screen = WindowManager.shared.focusedScreen ?? OuchPanel.pointerScreen() else { return false }
        let visible = screen.visibleFrame
        var frame: NSRect
        var caret: Caret
        switch tip.place {
        case .menuBar:
            guard let button = Onboarding.shared.statusButton?.window?.frame,
                  let target = NSScreen.screens.first(where: {
                      $0.frame.contains(NSPoint(x: button.midX, y: button.midY))
                  }) else { return false }
            let targetVisible = target.visibleFrame
            var x = button.midX - size.width / 2
            x = min(max(x, targetVisible.minX + 8), targetVisible.maxX - size.width - 8)
            caret = .top(min(max(button.midX - x, 30), size.width - 30) - TipView.panelInset.leading)
            frame = NSRect(x: x, y: targetVisible.maxY - 4 + (TipView.panelInset.top - 10) - size.height,
                           width: size.width, height: size.height)
            screen = target
        default:
            caret = .bottom
            frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 18 + 28 + 16 - TipView.panelInset.bottom,
                           width: size.width, height: size.height)
        }
        host.rootView = TipView(tip: tip, inset: TipView.panelInset, caret: caret)
        let panelFrame = OuchPanel.frame(size: frame.size, on: screen, anchor: .origin(frame.origin),
                                         inset: TipView.panelInset).integral
        let shown = OuchPanel(role: .overlay(.floating, clickThrough: false), frame: panelFrame)
        shown.contentView = host
        shown.alphaValue = 0
        shown.orderFrontRegardless()
        animate(0.35) { shown.animator().alphaValue = 1 }
        panel?.orderOut(nil)
        panel = shown
        global = tip
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissGlobal() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
        return true
    }

    func dismissGlobal() {
        hideWork?.cancel()
        global = nil
        guard let hidden = panel else { return }
        panel = nil
        animate(0.2, changes: { hidden.animator().alphaValue = 0 }, completion: { hidden.orderOut(nil) })
    }
}
