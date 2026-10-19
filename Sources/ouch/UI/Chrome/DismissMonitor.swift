import AppKit
import SwiftUI

final class DismissMonitor {
    private var monitors: [Any] = []
    private var screenObserver: Any?

    func start(keeps: @escaping (NSWindow?) -> Bool, swallowsClick: Bool = false, screens: Bool = false,
               key: ((NSEvent) -> Bool)? = nil, close: @escaping () -> Void) {
        stop()
        if let key,
           let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0) ? nil : $0 }) {
            monitors.append(monitor)
        }
        let anyClick: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: anyClick, handler: { _ in
            close()
        }) { monitors.append(monitor) }
        let click: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: click, handler: { event in
            if keeps(event.window) { return event }
            close()
            return swallowsClick ? nil : event
        }) { monitors.append(monitor) }
        if screens {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in close() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}
