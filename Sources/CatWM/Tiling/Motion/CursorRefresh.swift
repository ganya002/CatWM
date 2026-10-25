import AppKit
import QuartzCore

final class CursorRefresh {
    private var work: DispatchWorkItem?

    func soon(after delay: Double = 0.08) {
        work?.cancel()
        let item = DispatchWorkItem { Self.post() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) // style-ok: debounce of cursor updates
    }

    private static func post() {
        guard NSEvent.pressedMouseButtons == 0,
              let here = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                                  mouseCursorPosition: here, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    static func isOurs(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Hotkeys.syntheticMarker
    }
}
