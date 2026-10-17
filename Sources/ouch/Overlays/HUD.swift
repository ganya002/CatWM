import AppKit
import SwiftUI

final class HUD {
    static let shared = HUD()
    private var panel: OuchPanel?
    private var host: NSHostingView<HUDView>?
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?
    private static var margin: CGFloat { Elevation.float.room }
    var avoid: NSRect?

    func show(_ text: String, layout: Layout? = nil, on screen: NSScreen?) {
        show(text, layout: layout, warning: false, on: screen)
    }

    func warn(_ text: String, on screen: NSScreen?) {
        show(text, layout: nil, warning: true, on: screen)
    }

    private func show(_ text: String, layout: Layout?, warning: Bool, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let p = panel ?? makePanel()
        panel = p
        let wasVisible = p.isVisible && p.alphaValue > 0.5
        model.text = text
        model.layout = layout
        model.warning = warning
        if !wasVisible { model.pops += 1; PerfMonitor.track("ui:hud", for: 0.5) }
        let host = host ?? NSHostingView(rootView: HUDView(model: model, margin: Self.margin))
        if self.host == nil { self.host = host; p.contentView = host }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        if let avoid, frame.insetBy(dx: Self.margin, dy: Self.margin).intersects(avoid) {
            let below = avoid.minY - frame.height + Self.margin - 12
            frame.origin.y = below >= screen.visibleFrame.minY ? below : avoid.maxY - Self.margin + 12
        }
        p.place(size: frame.size, on: screen, anchor: .origin(frame.origin), inset: EdgeInsets(all: Self.margin))
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p?.animator().alphaValue = 0
            }, completionHandler: {
                if let p, p.alphaValue == 0 { p.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warning ? 1.6 : layout == nil ? 0.8 : 1), execute: work)
    }

    private func makePanel() -> OuchPanel { OuchPanel(role: .hud) }
}
