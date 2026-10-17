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
        var screen = WindowManager.shared.focusedScreen ?? OuchPanel.pointerScreen()
        let v = screen.visibleFrame
        var frame: NSRect
        var caret: Caret
        switch tip.place {
        case .menuBar:
            guard let b = Onboarding.shared.statusButton?.window?.frame,
                  let target = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: b.midX, y: b.midY)) }) else { return false }
            let tv = target.visibleFrame
            var x = b.midX - size.width / 2
            x = min(max(x, tv.minX + 8), tv.maxX - size.width - 8)
            caret = .top(min(max(b.midX - x, 30), size.width - 30) - TipView.panelInset.leading)
            frame = NSRect(x: x, y: tv.maxY - 4 + (TipView.panelInset.top - 10) - size.height, width: size.width, height: size.height)
            screen = target
        default:
            caret = .bottom
            frame = NSRect(x: v.midX - size.width / 2, y: v.minY + 18 + 28 + 16 - TipView.panelInset.bottom,
                           width: size.width, height: size.height)
        }
        host.rootView = TipView(tip: tip, inset: TipView.panelInset, caret: caret)
        let p = OuchPanel(role: .overlay(.floating, clickThrough: false),
                          frame: OuchPanel.frame(size: frame.size, on: screen, anchor: .origin(frame.origin), inset: TipView.panelInset).integral)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.35) { p.animator().alphaValue = 1 }
        panel?.orderOut(nil)
        panel = p
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
        guard let p = panel else { return }
        panel = nil
        animate(0.2, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
}
