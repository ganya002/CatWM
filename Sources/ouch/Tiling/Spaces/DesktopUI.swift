import AppKit

enum DesktopUI {
    static let owners = ["com.apple.WindowManager", "com.apple.dock"]

    static func missionControlDisplays() -> [AXUIElement] {
        owners.flatMap { bundle in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
                return [AXUIElement]()
            }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            return root.elements(kAXChildrenAttribute).flatMap { child -> [AXUIElement] in
                if child.string("AXIdentifier") == "mc.display" { return [child] }
                if child.string("AXIdentifier") == "mc" {
                    return child.elements(kAXChildrenAttribute).filter { $0.string("AXIdentifier") == "mc.display" }
                }
                return []
            }
        }
    }

    static func isBusy(on screen: Screen) -> Bool {
        let pids = Set(owners.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .map(\.processIdentifier))
        guard !pids.isEmpty else { return true }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0, layer != 20,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            let overlap = frame.intersection(screen.frame)
            return !overlap.isNull && overlap.width * overlap.height > screen.frame.width * screen.frame.height * 0.8
        }
    }

    static func isSettled(_ screen: Screen) -> Bool {
        !isBusy(on: screen) && DesktopBridge.isIdle(display: screen.uuid)
    }
}
