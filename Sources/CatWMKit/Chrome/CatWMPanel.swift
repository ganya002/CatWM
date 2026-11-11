import AppKit
import SwiftUI

package final class CatWMPanel: NSPanel {
    package enum Role {
        case menu
        case tooltip
        case hud
        case fullscreenFX
        case pointer
        case overlay(NSWindow.Level, clickThrough: Bool)
        case card(NSWindow.Level)
        case attached
    }

    package let role: Role
    package var onClose: (() -> Void)?

    package init(role: Role, frame: NSRect = .zero) {
        self.role = role
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let base: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        switch role {
        case .menu:
            level = .popUpMenu
            collectionBehavior = base.union(.transient)
        case .tooltip:
            level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            collectionBehavior = base.union(.transient)
            ignoresMouseEvents = true
        case .hud:
            level = .statusBar
            collectionBehavior = base.union(.transient)
            ignoresMouseEvents = true
        case .fullscreenFX:
            level = .screenSaver
            collectionBehavior = base.union(.stationary)
            ignoresMouseEvents = true
        case .pointer:
            level = .screenSaver
            collectionBehavior = base.union(.stationary)
            becomesKeyOnlyIfNeeded = true
            animationBehavior = .none
        case let .overlay(windowLevel, clickThrough):
            level = windowLevel
            collectionBehavior = base
            ignoresMouseEvents = clickThrough
        case let .card(windowLevel):
            level = windowLevel
            collectionBehavior = base
        case .attached:
            level = .normal
            collectionBehavior = [.transient, .ignoresCycle]
            animationBehavior = .none
        }
    }

    package override var canBecomeKey: Bool {
        switch role {
        case .menu, .card, .pointer: true
        default: false
        }
    }
    package override var canBecomeMain: Bool { false }

    package static func contained(_ frame: NSRect, in bounds: NSRect) -> NSRect {
        let width = min(frame.width, bounds.width), height = min(frame.height, bounds.height)
        return NSRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
    }

    package var containedDisplay = Instance.scope?.display

    private func fitted(_ frame: NSRect) -> NSRect? {
        guard let display = containedDisplay else { return frame }
        guard let screen = NSScreen.screens.first(where: { $0.displayUUID == display }) else { return nil }
        return Self.contained(frame, in: screen.frame)
    }

    private func showable() -> Bool {
        guard let target = fitted(frame) else { return false }
        if target != frame { super.setFrame(target, display: false) }
        return true
    }

    package override func orderFront(_ sender: Any?) { if showable() { super.orderFront(sender) } }
    package override func orderFrontRegardless() { if showable() { super.orderFrontRegardless() } }
    package override func makeKeyAndOrderFront(_ sender: Any?) { if showable() { super.makeKeyAndOrderFront(sender) } }
    package override func order(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if place == .out || showable() { super.order(place, relativeTo: other) }
    }

    package override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(fitted(frameRect) ?? frameRect, display: flag)
    }

    package override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(fitted(frameRect) ?? frameRect, display: displayFlag, animate: animateFlag)
    }

    package override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(fitted(NSRect(origin: point, size: frame.size))?.origin ?? point)
    }

    package override func setFrameTopLeftPoint(_ point: NSPoint) {
        let moved = NSRect(x: point.x, y: point.y - frame.height, width: frame.width, height: frame.height)
        guard let target = fitted(moved) else { return super.setFrameTopLeftPoint(point) }
        super.setFrameTopLeftPoint(NSPoint(x: target.minX, y: target.maxY))
    }

    package override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onClose, Self.isCloseKey(event) { onClose(); return true }
        return super.performKeyEquivalent(with: event)
    }

    package override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onClose { onClose() } else { super.keyDown(with: event) }
    }

    package override func cancelOperation(_ sender: Any?) {
        if let onClose { onClose() } else { super.cancelOperation(sender) }
    }

    private static func isCloseKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            && ["w", "q"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
    }

    package static func closeKeyWindow() -> Bool {
        guard let window = NSApp.keyWindow, window.isVisible else { return false }
        if let panel = window as? CatWMPanel {
            guard let close = panel.onClose else { return false }
            close()
            return true
        }
        guard window.styleMask.contains(.closable) else { return false }
        window.performClose(nil)
        return true
    }

    package static func pointerScreen() -> NSScreen? { screen(at: NSEvent.mouseLocation) }

    package static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    package enum Anchor {
        case center(dy: CGFloat = 0)
        case bottom(CGFloat)
        case origin(NSPoint)
    }

    package static func frame(size: CGSize, on screen: NSScreen, anchor: Anchor,
                              inset: EdgeInsets = EdgeInsets()) -> NSRect {
        let visible = screen.visibleFrame
        let room = NSRect(x: visible.minX - inset.leading, y: visible.minY - inset.bottom,
                          width: visible.width + inset.leading + inset.trailing,
                          height: visible.height + inset.top + inset.bottom)
        let width = min(size.width, room.width), height = min(size.height, room.height)
        var origin: NSPoint
        switch anchor {
        case let .center(dy): origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2 + dy)
        case let .bottom(y): origin = NSPoint(x: visible.midX - width / 2, y: visible.minY + y)
        case let .origin(point): origin = point
        }
        origin.x = min(max(origin.x, room.minX), room.maxX - width)
        origin.y = min(max(origin.y, room.minY), room.maxY - height)
        return NSRect(origin: origin, size: CGSize(width: width, height: height))
    }

    @discardableResult
    package func place(size: CGSize, on screen: NSScreen, anchor: Anchor, inset: EdgeInsets = EdgeInsets(),
                       display: Bool = true) -> NSRect {
        let frame = Self.frame(size: size, on: screen, anchor: anchor, inset: inset)
        setFrame(frame, display: display)
        return frame
    }
}

extension NSWindow {
    package func clearTitlebar(hiding buttons: [NSWindow.ButtonType]) {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in buttons { standardWindowButton(button)?.isHidden = true }
    }
}

@MainActor package final class DismissMonitor {
    private var monitors: [Any] = []
    private var screenObserver: Any?

    package init() {}

    package func start(keeps: @escaping (NSWindow?) -> Bool, swallowsClick: Bool = false, screens: Bool = false,
                       key: ((NSEvent) -> Bool)? = nil, close: @escaping @MainActor () -> Void) {
        stop()
        if let key,
           let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0) ? nil : $0 }) {
            monitors.append(monitor)
        }
        let anyClick: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: anyClick, handler: { _ in
            close()
        }) { monitors.append(monitor) }
        let click: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: click, handler: { event in
            if keeps(event.window) { return event }
            close()
            return swallowsClick && event.type != .rightMouseDown ? nil : event
        }) { monitors.append(monitor) }
        if screens {
            screenObserver = NotificationCenter.default.observeOnMain(
                NSApplication.didChangeScreenParametersNotification
            ) { close() }
        }
    }

    package func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}
