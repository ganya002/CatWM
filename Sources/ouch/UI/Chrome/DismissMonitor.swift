import AppKit
import SwiftUI

final class DismissMonitor {
    private var monitors: [Any] = []
    private var screenObserver: Any?

    func start(keeps: @escaping (NSWindow?) -> Bool, swallowsClick: Bool = false, screens: Bool = false,
               key: ((NSEvent) -> Bool)? = nil, close: @escaping () -> Void) {
        stop()
        if let key, let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0) ? nil : $0 }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
            close()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in
            if keeps(e.window) { return e }
            close()
            return swallowsClick ? nil : e
        }) { monitors.append(m) }
        if screens {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { _ in close() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
    }
}
