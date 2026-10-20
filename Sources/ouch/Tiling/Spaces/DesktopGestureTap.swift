import AppKit

final class DesktopGestureTap {
    struct Sample {
        let phase: Int64
        let progress: Double
        let velocity: Double
    }
    var enabled: () -> Bool = { false }
    var receive: (Sample) -> Void = { _ in }
    var interrupted: () -> Void = {}
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tracking = false
    private var natural = true

    func start() {
        guard tap == nil else { return }
        let mask = (CGEventMask(1) << 29) | (CGEventMask(1) << 30)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<DesktopGestureTap>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tracking = false
            interrupted()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard event.getIntegerValueField(.eventSourceUserData) != DesktopSwipe.tag else { return pass }
        let kind = event.getIntegerValueField(DesktopSwipe.field(55))
        if kind == 29 && tracking { return nil }
        guard kind == 30, event.getIntegerValueField(DesktopSwipe.field(110)) == 23,
              event.getIntegerValueField(DesktopSwipe.field(123)) == 1 else { return pass }
        let phase = event.getIntegerValueField(DesktopSwipe.field(132))
        if phase == 1 {
            guard enabled(), event.flags.isDisjoint(with: Hotkeys.tapMods),
                  let screen = Screen.all().first(where: { $0.frame.contains(mouseLocation()) }),
                  !Spaces.isFullscreen(display: screen.uuid), DesktopUI.isSettled(screen) else { return pass }
            tracking = true
            natural = DesktopSwipe.naturalScroll()
        }
        guard tracking else { return pass }
        let raw = event.getDoubleValueField(DesktopSwipe.field(124))
        let velocity = event.getDoubleValueField(DesktopSwipe.field(129))
        let sign = DesktopSwipe.augmented && natural ? -1.0 : 1.0
        if raw.isFinite, velocity.isFinite {
            receive(Sample(phase: phase, progress: raw * sign / 2, velocity: velocity * sign / 2))
        }
        if phase == 4 || phase == 8 {
            tracking = false
            return finish(event)
        }
        return nil
    }

    private func finish(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard DesktopSwipe.augmented else { return nil }
        for field: UInt32 in [124, 129, 130] { event.setDoubleValueField(DesktopSwipe.field(field), value: 0) }
        return Unmanaged.passUnretained(event)
    }
}
