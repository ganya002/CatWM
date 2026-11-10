import AppKit
import CatWMKit
import SwiftUI

final class SplitHandle {
    static let shared = SplitHandle()
    private var handles: [String: Handle] = [:]

    func update(instant: Bool = false) {
        let manager = WindowManager.shared
        let animate = !instant && manager.config.animate
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var shown = Set<String>()
        let screens = Screen.all()
        let present = Set(screens.map(\.uuid))
        for (uuid, handle) in handles where !present.contains(uuid) {
            handle.hide()
            handles[uuid] = nil
        }
        for screen in screens {
            guard let divider = manager.splitDivider(on: screen) else { continue }
            shown.insert(screen.uuid)
            let handle = handles[screen.uuid] ?? Handle(screen: screen.uuid)
            handles[screen.uuid] = handle
            handle.show(divider, duration: animate ? manager.config.animationDuration : 0,
                        above: manager.splitIDs(on: screen))
        }
        for (uuid, handle) in handles where !shown.contains(uuid) { handle.hide() }
    }

    func confirmSwap(on screen: String) { handles[screen]?.confirm() }

    private final class Handle {
        private static let confirmDuration = 0.5

        private let panel = CatWMPanel(role: .overlay(.normal, clickThrough: false))
        private let view: SplitHandleView
        private let glide = PanelGlide()
        private var target: NSRect?
        private var confirmEnd: DispatchWorkItem?

        init(screen: String) {
            view = SplitHandleView(screen: screen)
            panel.contentView = view
        }

        func show(_ divider: SplitDivider, duration: Double, above tiled: [CGWindowID]) {
            view.divider = divider
            if view.model.vertical != divider.vertical { view.model.vertical = divider.vertical }
            let frame = Self.frame(for: divider)
            defer { stack(above: tiled) }
            guard frame != target || !panel.isVisible else { return }
            target = frame
            if panel.isVisible, duration > 0, !view.model.dragging {
                var spec = MotionSpec(WindowManager.shared.config)
                spec.duration = duration
                glide.to(frame, on: panel, spec: spec)
            } else {
                glide.stop()
                panel.setFrame(frame, display: true)
            }
        }

        private func stack(above tiled: [CGWindowID]) {
            guard let top = CGWindowInfo.onScreen().first(where: { tiled.contains($0.id) }) else {
                if !panel.isVisible { panel.orderFrontRegardless() }
                return
            }
            panel.order(.above, relativeTo: Int(top.id))
        }

        func hide() {
            guard panel.isVisible else { return }
            view.cancelDrag()
            panel.orderOut(nil)
            target = nil
        }

        func confirm() {
            guard panel.isVisible else { return }
            confirmEnd?.cancel()
            view.model.confirming = true
            let end = DispatchWorkItem { [weak self] in self?.view.model.confirming = false }
            confirmEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDuration, execute: end)
        }

        private static func frame(for divider: SplitDivider) -> NSRect {
            let line = divider.frame, side = SplitGrip.width
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return divider.vertical
                ? NSRect(x: line.midX - side / 2, y: primaryHeight - line.maxY, width: side, height: line.height)
                : NSRect(x: line.minX, y: primaryHeight - line.midY - side / 2, width: line.width, height: side)
        }
    }
}

private final class SplitHandleView: NSView {
    private static let dragThreshold: CGFloat = 3

    let model = SplitGripModel()
    var divider: SplitDivider?
    private let screen: String
    private var start: CGPoint?
    private var grab: CGFloat = 0
    private var pending: CGFloat?
    private var hovered = false

    init(screen: String) {
        self.screen = screen
        super.init(frame: NSRect(x: 0, y: 0, width: SplitGrip.width, height: SplitGrip.width))
        let host = NSHostingView(rootView: SplitGrip(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        stripRect.contains(convert(point, from: superview)) ? self : nil
    }

    private var vertical: Bool { divider?.vertical ?? true }

    private var stripRect: NSRect {
        let side = SplitGrip.hitThickness
        return vertical ? NSRect(x: bounds.midX - side / 2, y: 0, width: side, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - side / 2, width: bounds.width, height: side)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    override func mouseExited(with _: NSEvent) {
        hovered = false
        if !model.dragging { ModeCursor.shared.hold(nil) }
    }

    private func updateCursor(_ event: NSEvent) {
        guard !model.dragging else { return }
        hovered = stripRect.contains(convert(event.locationInWindow, from: nil))
        ModeCursor.shared.hold(hovered ? (vertical ? .resizeLeftRight : .resizeUpDown) : nil)
    }

    override func mouseDown(with _: NSEvent) {
        guard let divider else { return }
        let point = mouseLocation()
        start = point
        grab = along(point, divider) - divider.position
    }

    override func mouseDragged(with _: NSEvent) {
        guard let start, let divider else { return }
        let point = mouseLocation()
        if !model.dragging {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold,
                  let screen = currentScreen() else { return }
            model.dragging = true
            WindowManager.shared.beginDividerDrag(on: screen)
        }
        let wasPending = pending != nil
        pending = along(point, divider) - grab
        if !wasPending { DispatchQueue.main.async { [weak self] in self?.flush() } }
    }

    override func mouseUp(with _: NSEvent) {
        guard start != nil else { return }
        if model.dragging {
            flush()
            WindowManager.shared.endDividerDrag()
        } else if let screen = currentScreen() {
            WindowManager.shared.swapSides(on: screen)
        }
        reset()
    }

    func cancelDrag() {
        if model.dragging { DispatchQueue.main.async { WindowManager.shared.endDividerDrag() } }
        reset()
    }

    private func reset() {
        start = nil
        pending = nil
        model.dragging = false
        if !hovered { ModeCursor.shared.hold(nil) }
    }

    private func flush() {
        guard let position = pending, let screen = currentScreen() else { return }
        pending = nil
        WindowManager.shared.moveDivider(on: screen, to: position)
    }

    private func currentScreen() -> Screen? { Screen.all().first { $0.uuid == screen } }

    private func along(_ point: CGPoint, _ divider: SplitDivider) -> CGFloat { divider.vertical ? point.x : point.y }
}
