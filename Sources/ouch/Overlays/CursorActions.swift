import AppKit
import SwiftUI

final class CursorActions {
    static let shared = CursorActions()

    private let model = CursorActionsModel()
    private var dotPanel: NSPanel?
    private var menuPanel: NSPanel?
    private var moveTap: CFMachPort?
    private var moveSource: CFRunLoopSource?
    private var lastFollow = CGPoint(x: -1, y: -1)
    private var shown = false
    private var opening = false
    private var closeWork: DispatchWorkItem?
    private static let dotSize = CursorActionsView.markSize

    private var enabled: Bool { WindowManager.shared.config.cursorActions }
    var isMenuOpen: Bool { model.open }

    func install() {
        Hotkeys.shared.onModifierTap = { [weak self] in self?.tapped() }
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


    func modeChanged(_ name: String) {
        dismissMenu()
        if name.isEmpty || !enabled { hide() } else { show() }
    }

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
        placeDot(at: NSEvent.mouseLocation)
        fadeDot(out: false)
    }


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

    private func fadeDot(out: Bool) {
        guard let dot = dotPanel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = out ? 0.09 : 0.18
            dot.animator().alphaValue = out ? 0 : 1
        }
    }

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

    fileprivate func follow(cgPoint: CGPoint) {
        guard shown, !model.open, !opening, menuPanel?.isVisible != true else { return }
        let p = CGPoint(x: cgPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - cgPoint.y)
        guard p != lastFollow else { return }
        lastFollow = p
        placeDot(at: p)
    }

    private func placeDot(at point: CGPoint) {
        let side = Self.dotSize
        let o = CursorActionsView.markOffset
        dotPanel?.setFrameOrigin(CGPoint(x: (point.x + o.width - side / 2).rounded(), y: (point.y - o.height - side / 2).rounded()))
    }

    private func place(menu panel: NSPanel, at point: CGPoint) {
        let m = CursorActionsView.margin, gap: CGFloat = 10
        let size = CursorActionsView.menuSize(for: model.actions)
        let screen = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.frame ?? .zero
        var x = point.x + gap, top = point.y - gap
        if x + size.width > screen.maxX { x = point.x - gap - size.width }
        if top - size.height < screen.minY { top = point.y + gap + size.height }
        x = min(max(x, screen.minX), screen.maxX - size.width)
        top = min(max(top, screen.minY + size.height), screen.maxY)
        let frame = CGRect(x: (x - m).rounded(), y: (top - size.height - m).rounded(),
                           width: size.width + 2 * m, height: size.height + 2 * m)
        panel.setFrame(frame, display: true)
        model.anchor = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

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
        let host = FirstClickHost(rootView: CursorActionsView(model: model))
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.animationBehavior = .none
        return p
    }
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

private final class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
