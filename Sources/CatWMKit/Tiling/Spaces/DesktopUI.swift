import AppKit

package enum DesktopUI {
    package static let owners = ["com.apple.WindowManager", "com.apple.dock"]

    package static func prepare() {
        DesktopMenuBar.recover()
        DesktopMenuBarCover.shared.prepare()
        for screen in Screen.all() { _ = isSettled(screen) }
    }

    package static func isBusy(on screen: Screen) -> Bool {
        isBusy(on: [screen])
    }

    package static func isBusy(on screens: [Screen]) -> Bool {
        guard !screens.isEmpty else { return false }
        let pids = Set(owners.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .map(\.processIdentifier))
        guard !pids.isEmpty else { return true }
        return isBusy(WindowServerQuery.onScreenWindows(), ownedBy: pids, on: screens.map(\.frame)) {
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        }
    }

    package static func isBusy(_ windows: [WindowServerQuery.WindowInfo]?, ownedBy pids: Set<pid_t>,
                               on frames: [CGRect],
                               fallback: () -> [[String: Any]]) -> Bool {
        guard !frames.isEmpty else { return false }
        guard !pids.isEmpty else { return true }
        guard let windows, !windows.contains(where: {
            $0.pid == 0 && coversDisplay($0.bounds, level: $0.level, on: frames)
        }) else { return isBusy(fallback(), ownedBy: pids, on: frames) }
        return windows.contains {
            pids.contains($0.pid) && coversDisplay($0.bounds, level: $0.level, on: frames)
        }
    }

    package static func isBusy(_ windows: [[String: Any]], ownedBy pids: Set<pid_t>, on frames: [CGRect]) -> Bool {
        guard !frames.isEmpty else { return false }
        guard !pids.isEmpty else { return true }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return coversDisplay(frame, level: layer, on: frames)
        }
    }

    private static func coversDisplay(_ frame: CGRect, level: Int, on screens: [CGRect]) -> Bool {
        guard level >= 0, level != 20 else { return false }
        return screens.contains { screen in
            let overlap = frame.intersection(screen)
            return !overlap.isNull && overlap.width * overlap.height > screen.width * screen.height * 0.8
        }
    }

    package static func isSettled(_ screen: Screen) -> Bool {
        !isBusy(on: screen) && DesktopBridge.isIdle(display: screen.uuid)
    }
}
