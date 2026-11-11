import AppKit

@MainActor package final class DockWindowPull {
    package var prepare: ((CGPoint) -> (@MainActor @Sendable () -> Void)?)?
    package var post: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: (down: CGEvent, action: @MainActor @Sendable () -> Void)?
    private var hold: DispatchWorkItem?
    private static let replayMarker: Int64 = 0x4f55_4348_444f_434b

    @discardableResult
    package func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DockWindowPull>.fromOpaque(context).takeUnretainedValue()
            return onMainThread { owner.intercept(type, event) } ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    package func stop() {
        guard let tap else { return }
        setEnabled(false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    package var isInstalled: Bool { tap != nil }

    package func setEnabled(_ enabled: Bool) {
        guard let tap else { return }
        if !enabled { giveBackClick() }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    private func intercept(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return handle(type, event) }
        giveBackClick()
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return false
    }

    package func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else { return false }
        switch type {
        case .leftMouseDown:
            guard pending == nil,
                  event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
                  event.getIntegerValueField(.mouseEventClickState) <= 1,
                  let action = prepare?(event.location), let down = event.copy() else { return false }
            pending = (down, action)
            let work = DispatchWorkItem { [weak self] in self?.giveBackClick() }
            hold = work
            DispatchQueue.main.asyncAfter( // style-ok: a click becomes a hold after this time
                deadline: .now() + 0.35, execute: work
            )
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
            let distance = hypot(event.location.x - pending.down.location.x, event.location.y - pending.down.location.y)
            let close = distance <= 5
                && event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift])
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
