import AppKit
import SwiftUI

final class Tooltip {
    static let shared = Tooltip()

    private var panel: NSPanel?
    private weak var owner: NSView?
    private var work: DispatchWorkItem?
    private var lastHidden = Date.distantPast
    private var monitor: Any?
    private var watch: Timer?
    private static let margin: CGFloat = 30

    func hover(_ view: NSView, text: String, chords: [[String]]) {
        guard !text.isEmpty else { return }
        work?.cancel()
        owner = view
        let warm = Date().timeIntervalSince(lastHidden) < 0.6 || panel?.isVisible == true
        let item = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, self.owner === view else { return }
            self.show(over: view, text: text, chords: chords)
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0.05 : OTooltip.delay), execute: item)
    }

    func leave(_ view: NSView) {
        guard owner === view else { return }
        hide()
    }

    func hide() {
        work?.cancel()
        owner = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        watch?.invalidate()
        watch = nil
        guard let panel, panel.isVisible else { return }
        lastHidden = Date()
        panel.orderOut(nil)
    }

    private func show(over view: NSView, text: String, chords: [[String]]) {
        guard let window = view.window, window.isVisible else { return }
        let r = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, m = Self.margin

        let measure = NSHostingView(rootView: OTooltip(text: text, chords: chords, caret: .none))
        let tip = measure.fittingSize
        let x = min(max(r.midX - tip.width / 2, v.minX + 6), v.maxX - tip.width - 6)
        let gap: CGFloat = 14
        let above = r.maxY + gap + tip.height < v.maxY - 4
        let y = above ? r.maxY + gap : r.minY - gap - tip.height
        let caretX = min(max(r.midX - x, 14), tip.width - 14)
        let caret: Caret = above ? .bottomAt(caretX - tip.width / 2) : .top(caretX)

        let p = panel ?? makePanel()
        panel = p
        let frame = OuchPanel.frame(size: CGSize(width: tip.width + 2 * m, height: tip.height + 2 * m), on: screen,
                                    anchor: .origin(NSPoint(x: x - m, y: y - m)), inset: EdgeInsets(all: m))
        let host = NSHostingView(rootView: OTooltip(text: text, chords: chords, caret: caret).padding(m))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        p.contentView = host
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak view] _ in
            guard let self else { return }
            guard let view, let w = view.window, w.isVisible, w.occlusionState.contains(.visible),
                  w.convertToScreen(view.convert(view.bounds, to: nil)).contains(NSEvent.mouseLocation)
            else { self.hide(); return }
        }
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] e in
                self?.hide()
                return e
            }
        }
    }

    private func makePanel() -> NSPanel { OuchPanel(role: .tooltip) }
}
