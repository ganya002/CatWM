// MenuBar: draws the menu bar item's picture (workspace number and layout).
import AppKit

/// The menu bar item's picture: the focused display's workspace number, a small drawing of its
/// layout, and the icons of the apps on it. While a mode (submap) is on, the layout turns blue.
enum MenuBarIcon {
    static let maxApps = 6
    private static let height: CGFloat = 18
    private static let glyphSize = CGSize(width: 19, height: 13)
    private static let iconSize: CGFloat = 16
    private static var iconCache: [pid_t: NSImage] = [:]

    static func image(mode: String, workspace: String?, layout: Layout, pids: [pid_t]) -> NSImage {
        let wsText = workspace.map { NSAttributedString(string: $0, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.labelColor,
        ]) }
        let shown = Array(pids.prefix(maxApps))
        let extra = pids.count - shown.count
        let extraText = extra > 0 ? NSAttributedString(string: "+\(extra)", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
        ]) : nil

        // Lay out left to right; widths are known up front so the image can be sized.
        var parts: [(width: CGFloat, gapAfter: CGFloat, draw: (CGFloat) -> Void)] = []
        if let wsText {
            parts.append((ceil(wsText.size().width), 4, { x in draw(wsText, at: x) }))
        }
        parts.append((glyphSize.width, shown.isEmpty ? 0 : 5, { x in
            let r = CGRect(x: x, y: (height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height)
            drawLayout(layout, color: mode.isEmpty ? .labelColor : .systemBlue, in: r)
        }))
        for (i, pid) in shown.enumerated() {
            let icon = self.icon(for: pid)
            parts.append((iconSize, i == shown.count - 1 ? 2 : 1, { x in
                icon?.draw(in: CGRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
            }))
        }
        if let extraText {
            parts.append((ceil(extraText.size().width), 0, { x in draw(extraText, at: x) }))
        }
        if parts.last?.gapAfter ?? 0 > 0 { parts[parts.count - 1].gapAfter = 0 }

        let width = parts.reduce(0) { $0 + $1.width + $1.gapAfter }
        let image = NSImage(size: CGSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for p in parts {
                p.draw(x)
                x += p.width + p.gapAfter
            }
            return true
        }
        image.accessibilityDescription = (workspace.map { "Workspace \($0), " } ?? "") + layout.title
            + (mode.isEmpty ? "" : ", \(mode) mode")
        return image
    }

    /// Icons of apps that quit are dropped so the cache doesn't grow forever.
    static func pruneIcons(keeping pids: Set<pid_t>) {
        iconCache = iconCache.filter { pids.contains($0.key) || NSRunningApplication(processIdentifier: $0.key) != nil }
    }

    private static func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = icon
        return icon
    }

    private static func draw(_ text: NSAttributedString, at x: CGFloat) {
        let size = text.size()
        text.draw(at: CGPoint(x: x, y: (height - size.height) / 2))
    }

    /// How many panes (and main panes) each layout's drawing has: enough for its shape to show
    /// (a third column, a stack beside the main pane), so every layout looks different. Widescreen
    /// Tall only differs from Tall with several main windows, so it's drawn with two.
    private static func panes(_ layout: Layout) -> (count: Int, main: Int) {
        switch layout {
        case .fullscreen, .floating: (1, 1)
        case .twoPane, .twoPaneRight: (2, 1)
        case .tall, .tallRight, .wide, .column, .row: (3, 1)
        case .bsp: (4, 1)
        case .widescreenTall, .widescreenTallRight: (4, 2)
        case .threeColumnLeft, .threeColumnRight, .middleWide, .threeColumnMiddle: (5, 1)
        }
    }

    /// An outlined screen with the layout's panes inside; the main pane is solid and a little wider
    /// than the rest, so mirrored layouts (Tall / Tall Right) tell apart.
    private static func drawLayout(_ layout: Layout, color: NSColor, in r: CGRect) {
        let outline = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        color.withAlphaComponent(0.85).setStroke()
        outline.stroke()

        let inner = r.insetBy(dx: 2, dy: 2)
        let gap: CGFloat = 1
        // Layout frames are top-left origin; flip them into this bottom-left image.
        let (count, mains) = panes(layout)
        let frames = layout.frames(count: count, in: CGRect(origin: .zero, size: inner.size).insetBy(dx: -gap / 2, dy: -gap / 2),
                                   ratio: 0.55, mainCount: mains)?
            .map { f in CGRect(x: inner.minX + f.minX, y: inner.maxY - f.maxY, width: f.width, height: f.height).insetBy(dx: gap / 2, dy: gap / 2) }
        guard let frames else {
            // Floating: two overlapping windows.
            let a = CGRect(x: inner.minX, y: inner.midY - 1, width: inner.width * 0.6, height: inner.height / 2 + 1)
            let b = CGRect(x: inner.maxX - inner.width * 0.6, y: inner.minY, width: inner.width * 0.6, height: inner.height / 2 + 1)
            color.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: a, xRadius: 1, yRadius: 1).fill()
            color.setFill()
            NSBezierPath(roundedRect: b, xRadius: 1, yRadius: 1).fill()
            return
        }
        for (i, f) in frames.enumerated().reversed() {
            color.withAlphaComponent(i < mains ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect: f, xRadius: 1, yRadius: 1).fill()
        }
    }
}
