import AppKit

func axCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                _: UnsafeMutableRawPointer?) {
    WindowManager.shared.handle(notification as String, element)
}
