import AppKit

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

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
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
