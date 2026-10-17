import AppKit
import QuartzCore

enum CursorRefresh {
    private static var work: DispatchWorkItem?

    static func soon(after delay: Double = 0.08) {
        work?.cancel()
        let w = DispatchWorkItem { post() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private static func post() {
        guard NSEvent.pressedMouseButtons == 0,
              let here = CGEvent(source: nil)?.location,
              let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                              mouseCursorPosition: here, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    static func isOurs(_ e: NSEvent) -> Bool {
        e.cgEvent?.getIntegerValueField(.eventSourceUserData) == Hotkeys.syntheticMarker
    }
}
