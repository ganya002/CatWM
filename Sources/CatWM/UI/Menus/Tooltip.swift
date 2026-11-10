import AppKit
import CatWMKit
import SwiftUI

final class Tooltip {
    static let shared = Tooltip()

    private var panel: NSPanel?
    private weak var owner: NSView?
    private var work: DispatchWorkItem?
    private var lastHidden = Date.distantPast
    private var monitor: Any?
    private var watch: Timer?
    private static var margin: CGFloat { Elevation.popover.room }

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
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame, margin = Self.margin

        let measure = NSHostingView(rootView: OTooltip(text: text, chords: chords, caret: .none))
        let tip = measure.fittingSize
        let x = min(max(rect.midX - tip.width / 2, visible.minX + 6), visible.maxX - tip.width - 6)
        let gap: CGFloat = 14
        let above = rect.maxY + gap + tip.height < visible.maxY - 4
        let y = above ? rect.maxY + gap : rect.minY - gap - tip.height
        let caretX = min(max(rect.midX - x, 14), tip.width - 14)
        let caret: Caret = above ? .bottomAt(caretX - tip.width / 2) : .top(caretX)

        let tipPanel = panel ?? makePanel()
        panel = tipPanel
        let frame = CatWMPanel.frame(size: CGSize(width: tip.width + 2 * margin, height: tip.height + 2 * margin),
                                    on: screen, anchor: .origin(NSPoint(x: x - margin, y: y - margin)),
                                    inset: EdgeInsets(all: margin))
        let host = NSHostingView(rootView: OTooltip(text: text, chords: chords, caret: caret).padding(margin))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        tipPanel.contentView = host
        tipPanel.setFrame(frame, display: true)
        tipPanel.orderFrontRegardless()
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak view] _ in
            guard let self else { return }
            guard let view, let window = view.window, window.isVisible, window.occlusionState.contains(.visible),
                  window.convertToScreen(view.convert(view.bounds, to: nil)).contains(NSEvent.mouseLocation)
            else { self.hide(); return }
        }
        if monitor == nil {
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
            monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.hide()
                return event
            }
        }
    }

    private func makePanel() -> NSPanel { CatWMPanel(role: .tooltip) }
}

extension View {
    func tooltip(_ text: String, keys: [String] = []) -> some View {
        background(TooltipReader(text: text, chords: keys.isEmpty ? [] : [keys]))
    }
}

struct TooltipReader: NSViewRepresentable {
    let text: String
    let chords: [[String]]

    func makeNSView(context _: Context) -> TooltipTrackingView { TooltipTrackingView() }
    func updateNSView(_ view: TooltipTrackingView, context _: Context) {
        view.text = text
        view.chords = chords
    }
    static func dismantleNSView(_ view: TooltipTrackingView, coordinator _: ()) { Tooltip.shared.leave(view) }
}

final class TooltipTrackingView: PassThroughView {
    var text = ""
    var chords: [[String]] = []
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(tracking)
        area = tracking
    }

    override func mouseEntered(with _: NSEvent) { Tooltip.shared.hover(self, text: text, chords: chords) }
    override func mouseExited(with _: NSEvent) { Tooltip.shared.leave(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Tooltip.shared.leave(self) }
    }
}

class PassThroughView: NSView {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}

struct OTooltip: View {
    static let delay = 0.5
    let text: String
    var chords: [[String]] = []
    var caret: Caret = .bottom

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(Theme.body(12.5)).oneLine()
                .frame(maxWidth: 240, alignment: .leading)
            if !chords.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .fixedSize()
            }
        }
        .surface(.extraSmall, caret: caret)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var tooltipExamples: some View {
        HStack(alignment: .top, spacing: Theme.Space.extraLarge) {
            OTooltip(text: "Retile", chords: [["Z"]], caret: .none).fixedSize()
            OTooltip(text: "Settings", chords: [["⌘", ","]], caret: .none).fixedSize()
            OTooltip(text: "Send feedback", caret: .none).fixedSize()
            OIconButton(symbol: "ladybug", label: "Send feedback", tip: true) {}
        }
    }
}
#endif
