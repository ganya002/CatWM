// Overlays: the window-mode dot beside the pointer and the quick-action menu a modifier tap opens there.
import AppKit
import SwiftUI

/// While a mode is on, a small dot follows the pointer so you can tell where the mouse's window actions go.
/// Tapping `$mod` (or the mode chord's modifier, ⌘ for ⌘⇪) opens a menu there with actions for the window
/// under the pointer; a second tap, Esc or a click outside closes it (a click outside also leaves the mode,
/// like any click). A small click-through panel with the mark follows the pointer; the menu has a panel of its own, which
/// takes clicks only while it is open. Neither becomes key, so focus stays with the app. `cursor-actions = false` turns it off.
final class CursorActions {
    static let shared = CursorActions()

    private let model = CursorActionsModel()
    /// The mark beside the pointer. Never resized, so it can't be caught half-way by the menu opening.
    private var dotPanel: NSPanel?
    /// The menu, placed and shown only while it is open or playing out.
    private var menuPanel: NSPanel?
    /// Mouse moves, seen as they happen, so the mark moves with the pointer and not after it.
    private var moveTap: CFMachPort?
    private var moveSource: CFRunLoopSource?
    private var lastFollow = CGPoint(x: -1, y: -1)
    private var shown = false
    /// The menu panel is placed but the view has not been told to open yet.
    private var opening = false
    /// Keeps the menu panel up until the view has played the menu out.
    private var closeWork: DispatchWorkItem?
    private static let dotSize = CursorActionsView.markSize

    private var enabled: Bool { WindowManager.shared.config.cursorActions }
    var isMenuOpen: Bool { model.open }

    /// Hooks into the key tap. Called once when the window manager starts.
    func install() {
        Hotkeys.shared.onModifierTap = { [weak self] in self?.tapped() }
        // Asked inside the tap, so it only reads; the menu closes a turn later.
        Hotkeys.shared.onEscape = { [weak self] in
            guard let self, model.open else { return false }
            DispatchQueue.main.async { [weak self] in self?.dismissMenu() }
            return true
        }
        model.onPick = { [weak self] action in
            self?.dismissMenu()
            DispatchQueue.main.async { action.run() }
        }
    }

    // MARK: Triggers

    /// A mode began or ended. The mark shows for the whole mode; a menu from before never carries over.
    func modeChanged(_ name: String) {
        dismissMenu()
        if name.isEmpty || !enabled { hide() } else { show() }
    }

    /// The mode's modifier was tapped: open the menu for the window under the pointer, or close it.
    func tapped() {
        guard enabled, !Hotkeys.shared.submap.isEmpty else { return }
        if model.open || opening { dismissMenu(); return }
        let point = NSEvent.mouseLocation
        guard let found = WindowManager.shared.quickActions(at: point) else {
            HUD.shared.show("No window here", on: nil)
            return
        }
        show()
        closeWork?.cancel()
        closeWork = nil
        model.title = found.title
        model.actions = found.actions
        model.hovered = nil
        let menu = menuPanel ?? makeMenuPanel()
        menuPanel = menu
        place(menu: menu, at: point)
        menu.ignoresMouseEvents = false
        menu.orderFrontRegardless()
        fadeDot(out: true)
        // A turn later: the view first lays out closed in its panel, so the entrance has a start to grow from.
        opening = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            opening = false
            if shown, !Hotkeys.shared.submap.isEmpty { model.open = true } else { closeMenuPanel() }
        }
    }

    func dismissMenu() {
        guard model.open || opening else { return }
        opening = false
        model.open = false
        model.hovered = nil
        menuPanel?.ignoresMouseEvents = true
        let work = DispatchWorkItem { [weak self] in self?.closeMenuPanel() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func closeMenuPanel() {
        closeWork?.cancel()
        closeWork = nil
        menuPanel?.orderOut(nil)
        menuPanel?.ignoresMouseEvents = true
        guard shown else { return }
        placeDot(at: NSEvent.mouseLocation) // the pointer may have left while the menu was up
        fadeDot(out: false)
    }

    // MARK: Panels

    private func show() {
        guard !shown else { return }
        shown = true
        model.modGlyph = Self.glyph(of: WindowManager.shared.config.mainMod)
        let dot = dotPanel ?? makeDotPanel()
        dotPanel = dot
        dot.alphaValue = 1
        placeDot(at: NSEvent.mouseLocation)
        dot.orderFrontRegardless()
        startMoveTap()
    }

    private func hide() {
        stopMoveTap()
        guard shown else { return }
        shown = false
        closeMenuPanel()
        dotPanel?.orderOut(nil)
    }

    /// The mark leaves as the menu unfolds from its place, and comes back once the menu is gone.
    private func fadeDot(out: Bool) {
        guard let dot = dotPanel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = out ? 0.09 : 0.18
            dot.animator().alphaValue = out ? 0 : 1
        }
    }

    /// A listen-only tap for mouse moves and drags. A global monitor gets them a frame or two late and in
    /// bursts, and a timer reads the pointer up to a tick late; the tap sees each move as it happens.
    private func startMoveTap() {
        guard moveTap == nil else { return }
        let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: cursorMoveCallback, userInfo: nil) else { return }
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        moveTap = t
        moveSource = src
    }

    private func stopMoveTap() {
        if let t = moveTap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let src = moveSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        moveTap = nil
        moveSource = nil
    }

    fileprivate func reenableMoveTap() {
        if let t = moveTap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    /// The mark stays where the menu opened while the menu is up. `cgPoint` is global, y down from the top
    /// of the main display, as an event has it.
    fileprivate func follow(cgPoint: CGPoint) {
        guard shown, !model.open, !opening, menuPanel?.isVisible != true else { return }
        let p = CGPoint(x: cgPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - cgPoint.y)
        guard p != lastFollow else { return }
        lastFollow = p
        placeDot(at: p)
    }

    /// The mark's panel is centred on the spot `markOffset` right of the pointer's hot spot (`point`, global, y up).
    private func placeDot(at point: CGPoint) {
        let side = Self.dotSize
        let o = CursorActionsView.markOffset
        dotPanel?.setFrameOrigin(CGPoint(x: (point.x + o.width - side / 2).rounded(), y: (point.y - o.height - side / 2).rounded()))
    }

    /// The menu's panel fits the menu and its shadow margin, sits just below and right of the pointer, and
    /// flips to the other side of it near a screen edge, so no empty panel is left to catch clicks. Tells the
    /// view where the pointer is in the panel (y down).
    private func place(menu panel: NSPanel, at point: CGPoint) {
        let m = CursorActionsView.margin, gap: CGFloat = 10
        let size = CursorActionsView.menuSize(for: model.actions)
        let screen = OuchPanel.screen(at: point)
        let v = screen.visibleFrame // clear of the menu bar and the Dock
        var x = point.x + gap, top = point.y - gap
        if x + size.width > v.maxX { x = point.x - gap - size.width }
        if top - size.height < v.minY { top = point.y + gap + size.height }
        let frame = OuchPanel.frame(size: CGSize(width: size.width + 2 * m, height: size.height + 2 * m), on: screen,
                                    anchor: .origin(NSPoint(x: (x - m).rounded(), y: (top - size.height - m).rounded())),
                                    inset: EdgeInsets(all: m))
        panel.setFrame(frame, display: true)
        model.anchor = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    /// The key cap symbol for `$mod`: the first of ⌘ ⌥ ⌃ ⇧ it holds.
    private static func glyph(of flags: CGEventFlags) -> String {
        if flags.contains(.maskCommand) { return "⌘" }
        if flags.contains(.maskAlternate) { return "⌥" }
        if flags.contains(.maskControl) { return "⌃" }
        if flags.contains(.maskShift) { return "⇧" }
        return "⌥"
    }

    private func makeDotPanel() -> NSPanel {
        let p = Self.makePanel()
        p.ignoresMouseEvents = true
        let host = NSHostingView(rootView: CursorMarkView(model: model))
        p.setContentSize(CGSize(width: Self.dotSize, height: Self.dotSize))
        p.contentView = host
        return p
    }

    private func makeMenuPanel() -> NSPanel {
        let p = Self.makePanel()
        let host = OuchHostingView(rootView: CursorActionsView(model: model)) // never key, so the first click must press
        host.sizingOptions = [] // only `place` sizes the panel
        p.contentView = host
        return p
    }

    private static func makePanel() -> NSPanel { OuchPanel(role: .pointer) }
}

private func cursorMoveCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        CursorActions.shared.reenableMoveTap()
    } else {
        CursorActions.shared.follow(cgPoint: event.location)
    }
    return Unmanaged.passUnretained(event)
}
