// UI: pop-up menus, popovers and tooltips drawn on the glass Surface.
import AppKit
import SwiftUI

// Pop-up menus, popovers and tooltips everywhere in the app draw like the menu under the menu bar item:
// the same glass Surface, rows and keyboard, never the system's NSMenu, NSPopover or help tags.

// MARK: - Anchor

/// Finds where a SwiftUI view sits on screen, for hanging a pop-up off it.
final class ScreenAnchor: ObservableObject {
    weak var view: NSView?

    var screenRect: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct AnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context: Context) -> NSView { let v = PassThroughView(); anchor.view = v; return v }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

/// Takes no clicks, so it can sit behind a control.
private class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Pop-up panel

/// Shows pop-ups in borderless panels hung off a control: a menu or a small popover. One opened from inside
/// another stacks on it and leaves it open. Each closes on a click elsewhere, Esc, or a pick, and hands the
/// keyboard back to the window it came from.
final class Popup: NSObject, NSWindowDelegate {
    static let shared = Popup()

    private struct Entry {
        let panel: OuchPanel
        let generation: Int
        weak var parent: NSWindow?
        var onClose: (() -> Void)?
        let keys: (NSEvent) -> Bool
    }

    /// Open pop-ups, the innermost last.
    private var stack: [Entry] = []
    private let dismiss = DismissMonitor()
    /// Room around the surface for its shadow.
    private static let margin: CGFloat = 26

    var isOpen: Bool { !stack.isEmpty }
    /// Counts pop-ups shown, so a popover only closes the pop-up it opened.
    private(set) var generation = 0

    /// A menu of `items` under (or, without room, over) `anchor`, its leading edge on the control's.
    func menu(_ items: @escaping () -> [MenuItem], from anchor: NSRect, minWidth: CGFloat = 0, onClose: (() -> Void)? = nil) {
        let model = MenuModel()
        model.searchable = false
        model.source = items
        model.rebuild()
        let width = max(minWidth, MenuItem.fitWidth(model.items))

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, m = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(anchor.minX - 4, v.minX + 8), v.maxX - width - 8)
        model.opensLeft = left + width + subs > v.maxX - 8
        let below = anchor.minY - v.minY, above = v.maxY - anchor.maxY
        let fromBottom = below < 260 && above > below
        let height = min(fromBottom ? above : below, 820)
        let x = model.opensLeft ? left - subs - m : left - m
        let frame = fromBottom
            ? NSRect(x: x, y: anchor.maxY + 4 - m / 4, width: width + subs + 2 * m, height: height)
            : NSRect(x: x, y: anchor.minY - 4 + m / 4 - height, width: width + subs + 2 * m, height: height)
        let view = MenuRoot(model: model, rootX: model.opensLeft ? subs + m : m, top: m / 4, size: frame.size,
                            rootWidth: width, fromBottom: fromBottom)
        let g = generation + 1
        model.close = { [weak self] in self?.close(generation: g) }
        show(AnyView(view), frame: frame, onClose: onClose) { e in Self.menuKey(e, model) }
        DispatchQueue.main.async { withAnimation(Motion.easeOut) { model.appeared = true } }
    }

    /// Any content on a `md` glass Surface under `anchor`, e.g. a list with its own colours.
    func popover<Content: View>(from anchor: NSRect, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        let host = NSHostingView(rootView: content().surface(.md, glass: true).padding(Self.margin)
            .font(Theme.body()).foregroundStyle(Theme.ink).tint(Theme.accent))
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, m = Self.margin
        let x = min(max(anchor.minX - 4 - m, v.minX + 8 - m), v.maxX - size.width + m - 8)
        let fitsBelow = anchor.minY - 4 - (size.height - 2 * m) > v.minY
        let y = fitsBelow ? anchor.minY - 4 + m - size.height : anchor.maxY + 4 - m
        show(AnyView(host.rootView), frame: NSRect(x: x, y: y, width: size.width, height: size.height), onClose: onClose) { _ in false }
    }

    private func show(_ view: AnyView, frame: NSRect, onClose: (() -> Void)?, keys: @escaping (NSEvent) -> Bool) {
        // Opened from inside a pop-up, it stacks on it; from anywhere else it replaces what is open.
        let key = NSApp.keyWindow
        if !stack.contains(where: { $0.panel === key }) { closeAll() }
        generation += 1
        // A fresh panel each time: the last one may still be fading out.
        let p = makePanel()
        let g = generation
        p.onClose = { [weak self] in self?.close(generation: g) } // ⌘W and ⌘Q close it, not Ouch or the window under it
        stack.append(Entry(panel: p, generation: generation, parent: key, onClose: onClose, keys: keys))
        p.contentView = OuchHostingView(rootView: view)
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    /// Closes the pop-up shown as `generation`, and any opened from it, if it is still open.
    func close(generation g: Int) {
        if let i = stack.firstIndex(where: { $0.generation == g }) { close(from: i) }
    }

    /// Closes the innermost pop-up.
    func close() { if !stack.isEmpty { close(from: stack.count - 1) } }

    func closeAll() { close(from: 0) }

    /// Closes the pop-up at `index` and everything above it, innermost first.
    private func close(from index: Int) {
        while stack.count > index {
            var entry = stack.removeLast()
            let panel = entry.panel
            let done = entry.onClose
            entry.onClose = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.contentView = nil
            })
            // Hand the keyboard to what it came from; a pop-up still open keeps it for itself.
            if let parent = entry.parent, parent.isVisible { parent.makeKey() }
            done?()
        }
        if stack.isEmpty { dismiss.stop() }
    }

    private func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        p.delegate = self
        return p
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let resigned = notification.object as? NSWindow,
              stack.contains(where: { $0.panel === resigned }) else { return }
        // The keyboard moving between pop-ups (into a child, or back to its parent) is no reason to close.
        // A sheet or alert opened from the pop-up takes it for good; the pop-up has done its job.
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.stack.firstIndex(where: { $0.panel === resigned }) else { return }
            if self.stack.contains(where: { $0.panel.isKeyWindow }) { return }
            self.close(from: i)
        }
    }

    private func installMonitors() {
        // A click outside every pop-up only closes them, like a native menu.
        dismiss.start(keeps: { [weak self] w in
            guard let self, let i = stack.firstIndex(where: { $0.panel === w }) else { return false }
            // A click in a pop-up closes only those opened from it.
            if i < stack.count - 1 { close(from: i + 1) }
            return true
        }, swallowsClick: true, key: { [weak self] e in
            guard let self, let top = stack.last, top.panel.isKeyWindow else { return false }
            if e.keyCode == 53 { if !top.keys(e) { close() }; return true } // keys(e) once: Esc steps back a level
            return top.keys(e)
        }, close: { [weak self] in self?.closeAll() })
    }

    /// ↑↓ move, → opens, ← goes back, ↩ picks, Esc goes back then closes.
    private static func menuKey(_ e: NSEvent, _ model: MenuModel) -> Bool {
        switch e.keyCode {
        case 126: model.move(-1)
        case 125: model.move(1)
        case 124: model.openHighlighted()
        case 123: _ = model.back()
        case 36, 76: model.runHighlighted()
        case 53: return model.back()
        default: return false
        }
        return true
    }
}

extension MenuItem {
    /// A root column wide enough for its longest row, between 180 and 360.
    static func fitWidth(_ items: [MenuItem]) -> CGFloat {
        let font = Theme.nsBody(13.5)
        let keyFont = NSFont.systemFont(ofSize: 13)
        var widest: CGFloat = 0
        for i in items where !i.hidden {
            var w = (i.label as NSString).size(withAttributes: [.font: font]).width
            if let value = i.value { w += 8 + (value as NSString).size(withAttributes: [.font: font]).width }
            if !i.shortcut.isEmpty { w += 16 + (i.shortcut.joined() as NSString).size(withAttributes: [.font: keyFont]).width }
            if i.kind == .sub { w += 18 }
            widest = max(widest, w)
        }
        // Row padding 10 each side, the lead slot 16 and its gap 10, the surface's 6 each side, and room
        // for key glyphs (⌥ ⌘), which fall back to a wider face than the one measured.
        return min(max(widest * 1.1 + 20 + 26 + 12 + 20, 180), 380)
    }
}

// MARK: - Menu button

/// A control that opens a pop-up menu of `items` on click. Its label is styled by the caller.
struct OMenuButton<Label: View>: View {
    let items: () -> [MenuItem]
    var minWidth: CGFloat = 0
    /// The label takes this style; plain by default.
    var style: OButtonStyle? = nil
    @ViewBuilder var label: Label
    @StateObject private var anchor = ScreenAnchor()
    @StateObject private var open = Flag()

    init(minWidth: CGFloat = 0, style: OButtonStyle? = nil, items: @escaping () -> [MenuItem], @ViewBuilder label: () -> Label) {
        self.items = items
        self.minWidth = minWidth
        self.style = style
        self.label = label()
    }

    var body: some View {
        let button = Button {
            guard !open.on, let r = anchor.screenRect else { return }
            open.on = true
            Popup.shared.menu(items, from: r, minWidth: minWidth) { [open] in open.on = false }
        } label: { label }
        Group {
            if let style { button.buttonStyle(style) } else { button.buttonStyle(.plain) }
        }
        .background(AnchorReader(anchor: anchor))
    }
}

/// A row in a popover list, lit on hover like a menu row; for rows that carry their own colours.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { MenuRowBody(configuration: configuration) }
}

private struct MenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    @StateObject private var hover = Flag()

    var body: some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(configuration.isPressed ? Theme.wellHover : hover.on ? Theme.well : .clear))
            .contentShape(Rectangle())
            .onHover { hover.on = $0 }
    }
}

/// A pill that shows the current choice and pops up the options as radio rows.
struct OMenuPicker<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let options = options, binding = $selection, lit = hover.on && enabled
        OMenuButton(items: {
            options.enumerated().map { n, o in
                MenuItem(id: "\(n)", kind: .radio, label: o.label, checked: o.value == binding.wrappedValue,
                         action: { binding.wrappedValue = o.value })
            }
        }) {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "").font(Theme.body(13)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).frame(height: Theme.controlHeight)
            .background(Capsule().fill(lit ? Theme.wellHover : Theme.well))
            .contentShape(Capsule())
        }
        .fixedSize()
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.fast), value: lit)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
    }
}

// MARK: - Popover

private final class PopoverState: ObservableObject { var generation = -1 }

private struct PopoverModifier<PopContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> PopContent
    @StateObject private var anchor = ScreenAnchor()
    @StateObject private var state = PopoverState()

    func body(content view: Content) -> some View {
        view
            .background(AnchorReader(anchor: anchor))
            .onChange(of: isPresented) { _, now in
                if now, let r = anchor.screenRect {
                    let binding = $isPresented
                    Popup.shared.popover(from: r, onClose: { binding.wrappedValue = false }, content: content)
                    state.generation = Popup.shared.generation
                } else if !now {
                    // Not a menu opened from inside the popover since.
                    Popup.shared.close(generation: state.generation)
                }
            }
    }
}

extension View {
    /// Opens `content` on a glass Surface under this view while `isPresented` holds.
    func oPopover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(PopoverModifier(isPresented: isPresented, content: content))
    }
}

// MARK: - Tooltip

/// Shows `OTooltip` over the view the pointer rests on. After one shows, the next one along shows at
/// once, like the system's help tags.
final class Tooltip {
    static let shared = Tooltip()

    private var panel: NSPanel?
    private weak var owner: NSView?
    private var work: DispatchWorkItem?
    private var lastHidden = Date.distantPast
    private var monitor: Any?
    /// Checks the pointer is still over the view: a window can close or move under a resting pointer
    /// without a mouse-exited event.
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
        // The caret reaches about 11pt past the pill, so leave room for it before the view.
        let gap: CGFloat = 14
        let above = r.maxY + gap + tip.height < v.maxY - 4
        let y = above ? r.maxY + gap : r.minY - gap - tip.height
        // The caret points at the middle of the view, wherever the tip had to shift to stay on screen.
        let caretX = min(max(r.midX - x, 14), tip.width - 14)
        let caret: Caret = above ? .bottomAt(caretX - tip.width / 2) : .top(caretX)

        let p = panel ?? makePanel()
        panel = p
        // The frame is set here alone: a hosting view left to size its window would resize it on layout
        // and slide the pill down over the view.
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

/// Watches the pointer over the view it sits behind; never takes a click.
private final class TooltipTrackingView: PassThroughView {
    var text = ""
    var chords: [[String]] = []
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { Tooltip.shared.hover(self, text: text, chords: chords) }
    override func mouseExited(with event: NSEvent) { Tooltip.shared.leave(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Tooltip.shared.leave(self) }
    }
}

private struct TooltipReader: NSViewRepresentable {
    let text: String
    let chords: [[String]]

    func makeNSView(context: Context) -> TooltipTrackingView { TooltipTrackingView() }
    func updateNSView(_ v: TooltipTrackingView, context: Context) {
        v.text = text
        v.chords = chords
    }
    static func dismantleNSView(_ v: TooltipTrackingView, coordinator: ()) { Tooltip.shared.leave(v) }
}

extension View {
    /// Ouch's tooltip: an inverted pill over the view after a short rest, with optional keys, e.g.
    /// `.tooltip("Retile windows", keys: ["⌥", "R"])`. An empty text shows nothing.
    func tooltip(_ text: String, keys: [String] = []) -> some View {
        background(TooltipReader(text: text, chords: keys.isEmpty ? [] : [keys]))
    }
}
