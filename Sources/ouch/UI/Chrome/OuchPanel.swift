import AppKit
import SwiftUI

final class OuchPanel: NSPanel {
    enum Role {
        case menu
        case tooltip
        case hud
        case fullscreenFX
        case pointer
        case overlay(NSWindow.Level, clickThrough: Bool)
        case card(NSWindow.Level)
    }

    let role: Role
    var onClose: (() -> Void)?

    init(role: Role, frame: NSRect = .zero) {
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
        case let .overlay(l, clickThrough):
            level = l
            collectionBehavior = base
            ignoresMouseEvents = clickThrough
        case let .card(l):
            level = l
            collectionBehavior = base
        }
    }

    override var canBecomeKey: Bool {
        switch role {
        case .menu, .card, .pointer: true
        default: false
        }
    }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onClose, Self.isCloseKey(event) { onClose(); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onClose { onClose() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        if let onClose { onClose() } else { super.cancelOperation(sender) }
    }

    private static func isCloseKey(_ e: NSEvent) -> Bool {
        e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            && ["w", "q"].contains(e.charactersIgnoringModifiers?.lowercased() ?? "")
    }

    static func closeKeyWindow() -> Bool {
        guard let w = NSApp.keyWindow, w.isVisible else { return false }
        if let p = w as? OuchPanel {
            guard let close = p.onClose else { return false }
            close()
            return true
        }
        guard w.styleMask.contains(.closable) else { return false }
        w.performClose(nil)
        return true
    }

    static func pointerScreen() -> NSScreen { screen(at: NSEvent.mouseLocation) }

    static func screen(at point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    enum Anchor {
        case center(dy: CGFloat = 0)
        case bottom(CGFloat)
        case origin(NSPoint)
    }

    static func frame(size: CGSize, on screen: NSScreen, anchor: Anchor, inset: EdgeInsets = EdgeInsets()) -> NSRect {
        let v = screen.visibleFrame
        let room = NSRect(x: v.minX - inset.leading, y: v.minY - inset.bottom,
                          width: v.width + inset.leading + inset.trailing, height: v.height + inset.top + inset.bottom)
        let w = min(size.width, room.width), h = min(size.height, room.height)
        var o: NSPoint
        switch anchor {
        case let .center(dy): o = NSPoint(x: v.midX - w / 2, y: v.midY - h / 2 + dy)
        case let .bottom(y): o = NSPoint(x: v.midX - w / 2, y: v.minY + y)
        case let .origin(p): o = p
        }
        o.x = min(max(o.x, room.minX), room.maxX - w)
        o.y = min(max(o.y, room.minY), room.maxY - h)
        return NSRect(origin: o, size: CGSize(width: w, height: h))
    }

    @discardableResult
    func place(size: CGSize, on screen: NSScreen, anchor: Anchor, inset: EdgeInsets = EdgeInsets(), display: Bool = true) -> NSRect {
        let f = Self.frame(size: size, on: screen, anchor: anchor, inset: inset)
        setFrame(f, display: display)
        return f
    }
}
