import AppKit
import QuartzCore

enum CursorRefresh {
    private static var work: DispatchWorkItem?

    static func soon(after delay: Double = 0.08) {
        work?.cancel()
        let item = DispatchWorkItem { post() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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
