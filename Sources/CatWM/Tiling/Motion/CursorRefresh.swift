import AppKit
import QuartzCore

final class CursorRefresh {
    private let backend: any WindowBackend
    private var work: DispatchWorkItem?

    init(backend: any WindowBackend) { self.backend = backend }

    func soon(after delay: Double = 0.08) {
        work?.cancel()
        let item = DispatchWorkItem { [backend] in backend.refreshCursor() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) // style-ok: debounce of cursor updates
    }

    static func post() {
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
