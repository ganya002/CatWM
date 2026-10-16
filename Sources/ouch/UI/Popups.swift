import AppKit
import SwiftUI

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

private class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class Popup: NSObject, NSWindowDelegate {
    static let shared = Popup()

    private struct Entry {
        let panel: OuchPanel
        let generation: Int
        weak var parent: NSWindow?
        var onClose: (() -> Void)?
        let keys: (NSEvent) -> Bool
    }

    private var stack: [Entry] = []
    private let dismiss = DismissMonitor()
    private static let margin: CGFloat = 26

    var isOpen: Bool { !stack.isEmpty }
    private(set) var generation = 0

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
        let key = NSApp.keyWindow
        if !stack.contains(where: { $0.panel === key }) { closeAll() }
        generation += 1
        let p = makePanel()
        let g = generation
        p.onClose = { [weak self] in self?.close(generation: g) }
        stack.append(Entry(panel: p, generation: generation, parent: key, onClose: onClose, keys: keys))
        p.contentView = OuchHostingView(rootView: view)
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close(generation g: Int) {
        if let i = stack.firstIndex(where: { $0.generation == g }) { close(from: i) }
    }

    func close() { if !stack.isEmpty { close(from: stack.count - 1) } }

    func closeAll() { close(from: 0) }

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
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.stack.firstIndex(where: { $0.panel === resigned }) else { return }
            if self.stack.contains(where: { $0.panel.isKeyWindow }) { return }
            self.close(from: i)
        }
    }

    private func installMonitors() {
        dismiss.start(keeps: { [weak self] w in
            guard let self, let i = stack.firstIndex(where: { $0.panel === w }) else { return false }
            if i < stack.count - 1 { close(from: i + 1) }
            return true
        }, swallowsClick: true, key: { [weak self] e in
            guard let self, let top = stack.last, top.panel.isKeyWindow else { return false }
            if e.keyCode == 53 { if !top.keys(e) { close() }; return true }
            return top.keys(e)
        }, close: { [weak self] in self?.closeAll() })
    }

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
        return min(max(widest * 1.1 + 20 + 26 + 12 + 20, 180), 380)
    }
}

struct OMenuButton<Label: View>: View {
    let items: () -> [MenuItem]
    var minWidth: CGFloat = 0
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

struct OMenuRowStyle: ButtonStyle {
    var highlighted: Bool? = nil
    var open = false
    var danger = false
    var bare = false

    func makeBody(configuration: Configuration) -> some View { OMenuRowBody(configuration: configuration, style: self) }
}

private struct OMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OMenuRowStyle
    @StateObject private var hover = Flag()

    var body: some View {
        let lit = style.highlighted ?? hover.on
        let fill: Color = configuration.isPressed ? Theme.wellHover
            : lit ? (style.danger ? Theme.dangerSoft : Theme.well)
            : style.open ? Theme.wellHover : .clear
        Group {
            if style.bare {
                configuration.label
            } else {
                configuration.label
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, maxHeight: Theme.rowHeight, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
    }
}

struct OMenuRow<Lead: View, Label: View, Trailing: View>: View {
    var highlighted: Bool? = nil
    var open = false
    var danger = false
    let action: () -> Void
    @ViewBuilder var lead: Lead
    @ViewBuilder var label: Label
    @ViewBuilder var trailing: Trailing

    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.highlighted = highlighted; self.open = open; self.danger = danger; self.action = action
        self.lead = lead(); self.label = label(); self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if Lead.self != EmptyView.self { lead.frame(width: 16) }
                label
                Spacer(minLength: 6)
                trailing
            }
            .font(Theme.body(13.5))
            .foregroundStyle(danger ? Theme.danger : Theme.ink)
        }
        .buttonStyle(OMenuRowStyle(highlighted: highlighted, open: open, danger: danger))
    }
}

extension OMenuRow where Trailing == EmptyView {
    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label) {
        self.init(highlighted: highlighted, open: open, danger: danger, action: action, lead: lead, label: label) { EmptyView() }
    }
}

extension OMenuRow where Lead == EmptyView {
    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.init(highlighted: highlighted, open: open, danger: danger, action: action, lead: { EmptyView() }, label: label,
                  trailing: trailing)
    }
}

struct OMenuPicker<T: Hashable>: View {
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
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).frame(height: Theme.controlHeight)
            .background(Capsule().fill(lit ? Theme.wellHover : Theme.well))
            .contentShape(Capsule())
        }
        .fixedSize()
        .onHover { hover.on = $0 }
        .animation(Motion.fade, value: lit)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
    }
}

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
                    Popup.shared.close(generation: state.generation)
                }
            }
    }
}

extension View {
    func oPopover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(PopoverModifier(isPresented: isPresented, content: content))
    }
}

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
    func tooltip(_ text: String, keys: [String] = []) -> some View {
        background(TooltipReader(text: text, chords: keys.isEmpty ? [] : [keys]))
    }
}
