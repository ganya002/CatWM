// UI: OuchPanel, the borderless panel under every Ouch menu, card and overlay, and what those panels share.
import AppKit
import SwiftUI

// MARK: - Panel

/// The borderless, non-activating panel that every Ouch menu, card and overlay is built on. The role sets the
/// level, how it acts on Spaces and over full-screen apps, and whether it takes clicks and the keyboard.
/// The content draws its own shadow and background. A panel with `onClose` closes itself on Esc, ⌘W and ⌘Q,
/// so those keys never quit Ouch while it has the keyboard.
final class OuchPanel: NSPanel {
    enum Role {
        /// Menus, pop-ups and the Sort panel: over all windows, takes the keyboard without activating Ouch.
        case menu
        /// The tooltip: over the menus too. Click-through.
        case tooltip
        /// A notice on the screen (the HUD, keyboard help). Click-through.
        case hud
        /// Over the whole screen and everything on it, fixed to its display (the mode effect). Click-through.
        case fullscreenFX
        /// Beside the pointer, over everything (the mode's dot and quick-action menu). Never takes the keyboard.
        case pointer
        /// A tour overlay, tip or toast at `level`. `clickThrough` lets the mouse reach what is below.
        case overlay(NSWindow.Level, clickThrough: Bool)
        /// A card that asks for an answer at `level`: takes the keyboard without activating Ouch, so Return
        /// reaches its default button.
        case card(NSWindow.Level)
    }

    let role: Role
    /// Esc, ⌘W and ⌘Q run this while the panel has the keyboard. Without it the keys go on to the app.
    var onClose: (() -> Void)?

    init(role: Role, frame: NSRect = .zero) {
        self.role = role
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // drawn by the content, so it follows the content's animations
        isReleasedWhenClosed = false
        // Ouch is rarely the active app; a panel shown while Settings is active must not vanish when you switch away.
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
        case .menu, .card: true
        default: false
        }
    }
    override var canBecomeMain: Bool { false }

    // MARK: Keys

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

    /// ⌘W or ⌘Q, on any keyboard layout.
    private static func isCloseKey(_ e: NSEvent) -> Bool {
        e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            && ["w", "q"].contains(e.charactersIgnoringModifiers?.lowercased() ?? "")
    }

    /// ⌘W and ⌘Q from the main menu: closes the key Ouch panel, or Settings. False when no window of
    /// Ouch's can close that way, so ⌘Q quits.
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

    // MARK: Placement

    /// The display under the pointer.
    static func pointerScreen() -> NSScreen { screen(at: NSEvent.mouseLocation) }

    /// The display that holds `point` (global, y up), or the main one.
    static func screen(at point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    enum Anchor {
        /// Centred on the visible area, moved up by `dy`.
        case center(dy: CGFloat = 0)
        /// Centred across, the frame's bottom edge `y` above the bottom of the visible area.
        case bottom(CGFloat)
        /// The frame's bottom-left corner, worked out by the caller.
        case origin(NSPoint)
    }

    /// The frame for a panel of `size` on `screen`. Only the transparent `inset` round the content (room for a
    /// shadow or caret) may hang past the visible area, under the menu bar or the Dock: a frame too big is cut
    /// to fit, one too far out moves in.
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

    /// Moves the panel to `frame(size:on:anchor:inset:)` and returns that frame.
    @discardableResult
    func place(size: CGSize, on screen: NSScreen, anchor: Anchor, inset: EdgeInsets = EdgeInsets(), display: Bool = true) -> NSRect {
        let f = Self.frame(size: size, on: screen, anchor: anchor, inset: inset)
        setFrame(f, display: display)
        return f
    }
}

extension EdgeInsets {
    /// The same inset on all four sides.
    init(all m: CGFloat) { self.init(top: m, leading: m, bottom: m, trailing: m) }
}

// MARK: - Hosting view

/// The SwiftUI host for panels that take clicks. Ouch is rarely the active app, so controls must take the
/// very first click; and the pointer goes back to the arrow when it leaves a text field.
class OuchHostingView<Content: View>: NSHostingView<Content> {
    private var keepsArrow = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !keepsArrow else { return }
        keepsArrow = true
        ArrowCursor.keep(in: self)
    }
}

// MARK: - Cursor

/// Puts the arrow back when the pointer goes from a text field to the rest of a view. AppKit updates the
/// pointer only for the key window of the active app, and Ouch's panels rarely are, so the I-beam stayed.
/// Leaves every other pointer (resize, link) alone.
final class ArrowCursor: NSResponder {
    private weak var view: NSView?
    private static var key = 0

    static func keep(in view: NSView) {
        let keeper = ArrowCursor()
        keeper.view = view
        // A tracking area does not retain its owner; the view does.
        objc_setAssociatedObject(view, &key, keeper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                            owner: keeper))
    }

    override func mouseEntered(with event: NSEvent) { update(event) }
    override func mouseMoved(with event: NSEvent) { update(event) }

    private func update(_ e: NSEvent) {
        let current = NSCursor.current
        guard current == NSCursor.iBeam || current == NSCursor.iBeamCursorForVerticalLayout,
              let content = view?.window?.contentView else { return }
        var hit = content.hitTest(content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow)
        while let v = hit {
            if v is NSText || v is NSTextField { return }
            hit = v.superview
        }
        NSCursor.arrow.set()
    }
}

// MARK: - Dismissing

/// Closes a panel that acts like a menu: a click in another app, or in an Ouch window it does not keep,
/// closes it. While it is up it also sees the key presses first. `stop()` removes it all.
final class DismissMonitor {
    private var monitors: [Any] = []
    private var screenObserver: Any?

    /// - keeps: true for a click in an Ouch window that must not close it, its own panel first.
    /// - swallowsClick: the click that closes it does nothing else, like a native menu.
    /// - screens: a change of displays closes it too.
    /// - key: a key press; true when it was handled and goes no further.
    func start(keeps: @escaping (NSWindow?) -> Bool, swallowsClick: Bool = false, screens: Bool = false,
               key: ((NSEvent) -> Bool)? = nil, close: @escaping () -> Void) {
        stop()
        if let key, let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0) ? nil : $0 }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
            close()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in
            if keeps(e.window) { return e }
            close()
            return swallowsClick ? nil : e
        }) { monitors.append(m) }
        if screens {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { _ in close() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
    }
}

// MARK: - Title bar

extension NSWindow {
    /// A title bar with no title and no fill, so the content runs up under it; `hiding` buttons are gone.
    func clearTitlebar(hiding buttons: [NSWindow.ButtonType]) {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in buttons { standardWindowButton(b)?.isHidden = true }
    }
}
