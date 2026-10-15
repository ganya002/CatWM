// Tiling: holds a Dock click to bring its window to the current workspace first.
import AppKit

/// Holds a plain Dock click long enough to bring its window here before macOS activates it.
/// A drag or long press is handed back to the Dock with the original mouse-down event.
final class DockWindowPull {
    var prepare: ((CGPoint) -> (() -> Void)?)?
    var post: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    private var tap: CFMachPort?
    private var pending: (down: CGEvent, action: () -> Void)?
    private var hold: DispatchWorkItem?
    private static let replayMarker: Int64 = 0x4f55_4348_444f_434b

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DockWindowPull>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.giveBackClick()
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Returns true only when Ouch consumes this event. Kept separate for the standalone probe.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else { return false }
        switch type {
        case .leftMouseDown:
            guard pending == nil,
                  event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
                  event.getIntegerValueField(.mouseEventClickState) <= 1,
                  let action = prepare?(event.location), let down = event.copy() else { return false }
            pending = (down, action)
            let work = DispatchWorkItem { [weak self] in self?.giveBackClick() }
            hold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            return true
        case .leftMouseDragged:
            guard let pending else { return false }
            if hypot(event.location.x - pending.down.location.x, event.location.y - pending.down.location.y) > 5 {
                giveBackClick()
                replay(event)
                return true
            }
            return true
        case .leftMouseUp:
            guard let pending else { return false }
            let close = hypot(event.location.x - pending.down.location.x, event.location.y - pending.down.location.y) <= 5
                && event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            hold?.cancel(); hold = nil
            self.pending = nil
            if close {
                DispatchQueue.main.async(execute: pending.action)
            } else {
                replay(pending.down)
                replay(event)
            }
            return true
        default:
            return false
        }
    }

    private func replay(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        post(event)
    }

    private func giveBackClick() {
        guard let pending else { return }
        hold?.cancel(); hold = nil
        self.pending = nil
        replay(pending.down)
    }
}

/// The screen edges where the Dock can take a click, so other clicks skip the Accessibility hit test.
/// Each band covers the Dock's whole edge on every display, sized for magnification. It does not
/// depend on whether an auto-hidden Dock shows now. Refreshes happen off the mouse tap path.
final class DockArea {
    private var bands: [CGRect]?
    private var refreshed = Date.distantPast
    private var refreshQueued = false
    private static let maxAge: TimeInterval = 10

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    /// Cheap enough for every mouse-down: no Accessibility, no Dock preference read once warmed.
    func contains(_ point: CGPoint) -> Bool {
        guard let bands else { refresh(); return self.bands?.contains { $0.contains(point) } ?? true }
        if Date().timeIntervalSince(refreshed) > Self.maxAge, !refreshQueued {
            refreshQueued = true // a Dock size or edge change with auto-hide sends no screen notification
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        return bands.contains { $0.contains(point) }
    }

    func refresh() {
        refreshQueued = false
        refreshed = Date()
        let dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dock)
        func number(_ key: String) -> CGFloat? { (CFPreferencesCopyAppValue(key as CFString, dock) as? NSNumber).map { CGFloat($0.doubleValue) } }
        let edge = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String ?? "bottom"
        let tile = number("tilesize") ?? 64
        let magnified = (CFPreferencesCopyAppValue("magnification" as CFString, dock) as? NSNumber)?.boolValue == true
        let icon = magnified ? max(tile, number("largesize") ?? 128) : tile
        guard let primary = NSScreen.screens.first else { bands = nil; return }
        let h = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        bands = Self.bands(screens: NSScreen.screens.map { (flip($0.frame), flip($0.visibleFrame)) }, edge: edge,
                           depth: min(max(icon, 16), 512) + 48)
    }

    /// Screen rects are in top-left-origin Quartz coordinates, like mouse event locations.
    /// A reserved Dock gap wider than `depth` wins. Each band reaches 1 pt past the edge.
    static func bands(screens: [(frame: CGRect, visible: CGRect)], edge: String, depth: CGFloat) -> [CGRect] {
        screens.map { f, v in
            switch edge {
            case "left":
                let d = max(depth, v.minX - f.minX)
                return CGRect(x: f.minX - 1, y: f.minY, width: d + 1, height: f.height)
            case "right":
                let d = max(depth, f.maxX - v.maxX)
                return CGRect(x: f.maxX - d, y: f.minY, width: d + 1, height: f.height)
            default:
                let d = max(depth, f.maxY - v.maxY)
                return CGRect(x: f.minX, y: f.maxY - d, width: f.width, height: d + 1)
            }
        }
    }
}
