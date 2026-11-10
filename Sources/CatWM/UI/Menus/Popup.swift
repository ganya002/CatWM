import AppKit
import CatWMKit
import SwiftUI

final class Popup: NSObject, NSWindowDelegate {
    static let shared = Popup()

    private struct Entry {
        let panel: CatWMPanel
        let generation: Int
        weak var parent: NSWindow?
        var onClose: (() -> Void)?
        let keys: (NSEvent) -> Bool
        let model: MenuModel?
    }

    private var stack: [Entry] = []
    private let dismiss = DismissMonitor()
    private static var margin: CGFloat { Elevation.popover.room }

    var isOpen: Bool { !stack.isEmpty }

    func owns(_ window: NSWindow?) -> Bool { stack.contains { $0.panel === window } }

    var windowNumbers: Set<Int> { Set(stack.map(\.panel.windowNumber)) }

    func hitsMenu(at point: CGPoint) -> Bool {
        guard let height = NSScreen.screens.first?.frame.height else { return false }
        return stack.contains { entry in
            guard let model = entry.model else { return false }
            let frame = entry.panel.frame
            let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - (height - point.y))
            let slack = Theme.Space.small
            return model.rowFrames.values.contains { $0.insetBy(dx: -slack, dy: -slack).contains(local) }
        }
    }

    private(set) var generation = 0

    func menu(_ items: @escaping () -> [MenuItem], from anchor: NSRect, minWidth: CGFloat = 0,
              onClose: (() -> Void)? = nil) {
        let model = MenuModel()
        model.searchable = false
        model.source = items
        model.rebuild()
        let width = max(minWidth, MenuItem.fitWidth(model.items))

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame, margin = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(anchor.minX - 4, visible.minX + 8), visible.maxX - width - 8)
        model.opensLeft = left + width + subs > visible.maxX - 8
        let below = anchor.minY - visible.minY, above = visible.maxY - anchor.maxY
        let fromBottom = below < 260 && above > below
        let height = min(fromBottom ? above : below, 820)
        let x = model.opensLeft ? left - subs - margin : left - margin
        let frame = fromBottom
            ? NSRect(x: x, y: anchor.maxY + 4 - margin, width: width + subs + 2 * margin, height: height)
            : NSRect(x: x, y: anchor.minY - 4 + margin - height, width: width + subs + 2 * margin, height: height)
        let view = MenuRoot(model: model, rootX: model.opensLeft ? subs + margin : margin, top: margin,
                            size: frame.size, rootWidth: width, fromBottom: fromBottom)
        let next = generation + 1
        model.close = { [weak self] in self?.close(generation: next) }
        show(AnyView(view), frame: frame, onClose: onClose, model: model) { event in Self.menuKey(event, model) }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.async { withAnimation(reduce ? Motion.fade : Motion.easeOut) { model.appeared = true } }
    }

    func context(_ items: @escaping () -> [MenuItem], onClose: (() -> Void)? = nil) {
        closeAll()
        let point = NSEvent.mouseLocation
        menu(items, from: NSRect(x: point.x + 4, y: point.y + 4, width: 0, height: 0), onClose: onClose)
    }

    func popover<Content: View>(from anchor: NSRect, onClose: (() -> Void)? = nil,
                                @ViewBuilder content: () -> Content) {
        let host = NSHostingView(rootView: content().surface(.medium).padding(Self.margin)
            .font(Theme.body()).foregroundStyle(Theme.ink).tint(Theme.accent))
        let size = host.fittingSize
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame, margin = Self.margin
        let x = min(max(anchor.minX - 4 - margin, visible.minX + 8 - margin), visible.maxX - size.width + margin - 8)
        let fitsBelow = anchor.minY - 4 - (size.height - 2 * margin) > visible.minY
        let y = fitsBelow ? anchor.minY - 4 + margin - size.height : anchor.maxY + 4 - margin
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        show(AnyView(host.rootView), frame: frame, onClose: onClose) { _ in false }
    }

    private func show(_ view: AnyView, frame: NSRect, onClose: (() -> Void)?, model: MenuModel? = nil,
                      keys: @escaping (NSEvent) -> Bool) {
        let key = NSApp.keyWindow
        if !stack.contains(where: { $0.panel === key }) { closeAll() }
        generation += 1
        let panel = makePanel()
        let current = generation
        panel.onClose = { [weak self] in self?.close(generation: current) }
        stack.append(Entry(panel: panel, generation: generation, parent: key, onClose: onClose, keys: keys,
                           model: model))
        let host = CatWMHostingView(rootView: view)
        host.sizingOptions = []
        panel.setFrame(frame, display: false)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close(generation target: Int) {
        if let i = stack.firstIndex(where: { $0.generation == target }) { close(from: i) }
    }

    func close() { if !stack.isEmpty { close(from: stack.count - 1) } }

    func closeAll() { close(from: 0) }

    private func close(from index: Int) {
        while stack.count > index {
            var entry = stack.removeLast()
            let panel = entry.panel
            let done = entry.onClose
            entry.onClose = nil
            Motion.fade(panel, to: 0, duration: Theme.fast) {
                panel.orderOut(nil)
                panel.contentView = nil
            }
            if let parent = entry.parent, parent.isVisible { parent.makeKey() }
            done?()
        }
        if stack.isEmpty { dismiss.stop() }
    }

    private func makePanel() -> CatWMPanel {
        let panel = CatWMPanel(role: .menu)
        panel.delegate = self
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let resigned = notification.object as? NSWindow,
              stack.contains(where: { $0.panel === resigned }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.stack.firstIndex(where: { $0.panel === resigned }) else { return }
            if self.stack.contains(where: \.panel.isKeyWindow) { return }
            self.close(from: i)
        }
    }

    private func installMonitors() {
        dismiss.start(keeps: { [weak self] window in
            guard let self, let i = stack.firstIndex(where: { $0.panel === window }) else { return false }
            if i < stack.count - 1 { close(from: i + 1) }
            return true
        }, swallowsClick: true, key: { [weak self] event in
            guard let self, let top = stack.last, top.panel.isKeyWindow else { return false }
            if event.keyCode == 53 { if !top.keys(event) { close() }; return true }
            return top.keys(event)
        }, close: { [weak self] in self?.closeAll() })
    }

    private static func menuKey(_ event: NSEvent, _ model: MenuModel) -> Bool {
        switch event.keyCode {
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

struct PopoverModifier<PopContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> PopContent
    @StateObject private var anchor = ScreenAnchor()
    @StateObject private var state = PopoverState()

    func body(content view: Content) -> some View {
        view
            .background(AnchorReader(anchor: anchor))
            .onChange(of: isPresented) { _, now in
                if now {
                    guard let rect = anchor.screenRect else { isPresented = false; return }
                    let binding = $isPresented
                    Popup.shared.popover(from: rect, onClose: { binding.wrappedValue = false }, content: content)
                    state.generation = Popup.shared.generation
                } else {
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

final class PopoverState: ObservableObject { var generation = -1 }

final class ScreenAnchor: ObservableObject {
    weak var view: NSView?

    var screenRect: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct AnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context _: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context _: Context) { anchor.view = nsView }
}

extension MenuItem {
    static func fitWidth(_ items: [MenuItem]) -> CGFloat {
        let font = Theme.nsBody(13.5)
        let keyFont = NSFont.systemFont(ofSize: 13)
        var widest: CGFloat = 0
        for item in items where !item.hidden {
            var width = item.label.size(withAttributes: [.font: font]).width
            if let value = item.value { width += 8 + value.size(withAttributes: [.font: font]).width }
            if !item.shortcut.isEmpty {
                width += 16 + item.shortcut.joined().size(withAttributes: [.font: keyFont]).width
            }
            if item.kind == .sub { width += 18 }
            widest = max(widest, width)
        }
        return min(max(widest * 1.1 + 20 + 26 + 12 + 20, 180), 380)
    }
}
