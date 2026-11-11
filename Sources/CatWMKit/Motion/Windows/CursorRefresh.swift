import AppKit
import QuartzCore

package final class CursorRefresh {
    private let backend: any WindowBackend
    private let pointerAndFocus: Bool
    private var work: DispatchWorkItem?

    package init(backend: any WindowBackend, pointerAndFocus: Bool) {
        self.backend = backend
        self.pointerAndFocus = pointerAndFocus
    }

    package func soon(after delay: Double = 0.08) {
        guard pointerAndFocus else { return }
        work?.cancel()
        let item = DispatchWorkItem { [backend] in backend.refreshCursor() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) // style-ok: debounce of cursor updates
    }

    package static func post() {
        guard RealInput.allows("cursor refresh", traps: false), NSEvent.pressedMouseButtons == 0,
              let here = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                                  mouseCursorPosition: here, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    package static func isOurs(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Hotkeys.syntheticMarker
    }
}
