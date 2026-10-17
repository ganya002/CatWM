import AppKit
import SwiftUI

final class SortOffer {
    static let shared = SortOffer()
    private var panel: OuchPanel?
    private var finish: ((Bool) -> Void)?
    private var timeout: DispatchWorkItem?

    func show(button: NSStatusBarButton?, on screen: NSScreen,
              done: @escaping (_ sort: Bool) -> Void) {
        finish = done
        let view = SortOfferView(caret: 0) { [weak self] in self?.end($0) }
        var host = OuchHostingView(rootView: view)
        let size = host.fittingSize
        let v = screen.visibleFrame
        var x = v.midX - size.width / 2, y = v.maxY - size.height - 16
        var caret: CGFloat = SortOfferView.width / 2
        if let b = button?.window?.frame {
            let card = SortOfferView.width
            let left = min(max(b.midX - card + 60, v.minX + 16), v.maxX - card - 16)
            x = left - SortOfferView.inset.leading
            y = b.minY - 10 - (size.height - SortOfferView.inset.top - SortOfferView.inset.bottom) - SortOfferView.inset.bottom
            caret = min(max(b.midX - left, 20), card - 20)
        }
        host = OuchHostingView(rootView: SortOfferView(caret: caret) { [weak self] in
            self?.end($0)
        })
        let p = OuchPanel(role: .overlay(.floating, clickThrough: false),
                          frame: OuchPanel.frame(size: size, on: screen, anchor: .origin(NSPoint(x: x, y: y)), inset: SortOfferView.inset).integral)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.35) { p.animator().alphaValue = 1 }
        panel = p
        let work = DispatchWorkItem { [weak self] in self?.end(false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func end(_ sort: Bool) {
        timeout?.cancel()
        timeout = nil
        guard let p = panel else { return }
        panel = nil
        let done = finish
        finish = nil
        animate(0.25, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        done?(sort)
    }
}
