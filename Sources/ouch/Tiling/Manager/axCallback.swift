import AppKit

func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _ refcon: UnsafeMutableRawPointer?) {
    WindowManager.shared.handle(notification as String, element)
}
