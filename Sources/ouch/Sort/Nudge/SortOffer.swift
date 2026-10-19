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
        let visible = screen.visibleFrame
        var x = visible.midX - size.width / 2, y = visible.maxY - size.height - 16
        var caret: CGFloat = SortOfferView.width / 2
        if let buttonFrame = button?.window?.frame {
            let card = SortOfferView.width
            let inset = SortOfferView.inset
            let left = min(max(buttonFrame.midX - card + 60, visible.minX + 16), visible.maxX - card - 16)
            x = left - inset.leading
            y = buttonFrame.minY - 10 - (size.height - inset.top - inset.bottom) - inset.bottom
            caret = min(max(buttonFrame.midX - left, 20), card - 20)
        }
        host = OuchHostingView(rootView: SortOfferView(caret: caret) { [weak self] in
            self?.end($0)
        })
        let card = OuchPanel(role: .overlay(.floating, clickThrough: false),
                             frame: OuchPanel.frame(size: size, on: screen, anchor: .origin(NSPoint(x: x, y: y)),
                                                    inset: SortOfferView.inset).integral)
        card.contentView = host
        card.alphaValue = 0
        card.orderFrontRegardless()
        animate(0.35) { card.animator().alphaValue = 1 }
        panel = card
        let work = DispatchWorkItem { [weak self] in self?.end(false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func end(_ sort: Bool) {
        timeout?.cancel()
        timeout = nil
        guard let card = panel else { return }
        panel = nil
        let done = finish
        finish = nil
        animate(0.25, changes: { card.animator().alphaValue = 0 }, completion: { card.orderOut(nil) })
        done?(sort)
    }
}
