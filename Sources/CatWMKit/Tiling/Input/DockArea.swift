import AppKit

@MainActor package final class DockArea {
    private var bands: [CGRect]?
    private var refreshed = Date.distantPast
    private var refreshQueued = false
    private static let maxAge: TimeInterval = 10

    private var screenObserver: NSObjectProtocol?

    package init() {}

    package func start() {
        refresh()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.observeOnMain(
            NSApplication.didChangeScreenParametersNotification
        ) { [weak self] in self?.refresh() }
    }

    package func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    package func contains(_ point: CGPoint) -> Bool {
        guard let bands else { refresh(); return self.bands?.contains { $0.contains(point) } ?? true }
        if Date().timeIntervalSince(refreshed) > Self.maxAge, !refreshQueued {
            refreshQueued = true
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        return bands.contains { $0.contains(point) }
    }

    package func refresh() {
        refreshQueued = false
        refreshed = Date()
        let dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dock)
        func number(_ key: String) -> CGFloat? {
            (CFPreferencesCopyAppValue(key as CFString, dock) as? Double).map { CGFloat($0) }
        }
        let edge = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String ?? "bottom"
        let tile = number("tilesize") ?? 64
        let magnified = (CFPreferencesCopyAppValue("magnification" as CFString, dock) as? Bool) == true
        let icon = magnified ? max(tile, number("largesize") ?? 128) : tile
        guard let primary = NSScreen.screens.first else { bands = nil; return }
        let height = primary.frame.height
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        bands = Self.bands(screens: NSScreen.screens.map { (flip($0.frame), flip($0.visibleFrame)) }, edge: edge,
                           depth: min(max(icon, 16), 512) + 48)
    }

    package static func bands(screens: [(frame: CGRect, visible: CGRect)], edge: String, depth: CGFloat) -> [CGRect] {
        screens.map { frame, visible in
            switch edge {
            case "left":
                let size = max(depth, visible.minX - frame.minX)
                return CGRect(x: frame.minX - 1, y: frame.minY, width: size + 1, height: frame.height)
            case "right":
                let size = max(depth, frame.maxX - visible.maxX)
                return CGRect(x: frame.maxX - size, y: frame.minY, width: size + 1, height: frame.height)
            default:
                let size = max(depth, frame.maxY - visible.maxY)
                return CGRect(x: frame.minX, y: frame.maxY - size, width: frame.width, height: size + 1)
            }
        }
    }
}
