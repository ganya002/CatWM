import AppKit

final class DockArea {
    private var bands: [CGRect]?
    private var refreshed = Date.distantPast
    private var refreshQueued = false
    private static let maxAge: TimeInterval = 10

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    func contains(_ point: CGPoint) -> Bool {
        guard let bands else { refresh(); return self.bands?.contains { $0.contains(point) } ?? true }
        if Date().timeIntervalSince(refreshed) > Self.maxAge, !refreshQueued {
            refreshQueued = true
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        return bands.contains { $0.contains(point) }
    }

    func refresh() {
        refreshQueued = false
        refreshed = Date()
        let dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dock)
        func number(_ key: String) -> CGFloat? { (CFPreferencesCopyAppValue(key as CFString, dock) as? NSNumber).map { CGFloat($0.doubleValue) } }
        let edge = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String ?? "bottom"
        let tile = number("tilesize") ?? 64
        let magnified = (CFPreferencesCopyAppValue("magnification" as CFString, dock) as? NSNumber)?.boolValue == true
        let icon = magnified ? max(tile, number("largesize") ?? 128) : tile
        guard let primary = NSScreen.screens.first else { bands = nil; return }
        let h = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        bands = Self.bands(screens: NSScreen.screens.map { (flip($0.frame), flip($0.visibleFrame)) }, edge: edge,
                           depth: min(max(icon, 16), 512) + 48)
    }

    static func bands(screens: [(frame: CGRect, visible: CGRect)], edge: String, depth: CGFloat) -> [CGRect] {
        screens.map { f, v in
            switch edge {
            case "left":
                let d = max(depth, v.minX - f.minX)
                return CGRect(x: f.minX - 1, y: f.minY, width: d + 1, height: f.height)
            case "right":
                let d = max(depth, f.maxX - v.maxX)
                return CGRect(x: f.maxX - d, y: f.minY, width: d + 1, height: f.height)
            default:
                let d = max(depth, f.maxY - v.maxY)
                return CGRect(x: f.minX, y: f.maxY - d, width: f.width, height: d + 1)
            }
        }
    }
}
