import AppKit
import CatWMKit

enum MenuBarIcon {
    private struct Part {
        let width: CGFloat
        var gapAfter: CGFloat
        let draw: (CGFloat) -> Void
    }

    static let maxApps = 6
    private static let height: CGFloat = 18
    private static let glyphSize = CGSize(width: 19, height: 13)
    private static let iconSize: CGFloat = 16

    static func image(mode: String, workspace: String?, layout: Layout, pids: [pid_t]) -> NSImage {
        let workspaceText = workspace.map { NSAttributedString(string: $0, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.labelColor
        ])
        }
        let shown = Array(pids.prefix(maxApps))
        let extra = pids.count - shown.count
        let extraText = extra > 0 ? NSAttributedString(string: "+\(extra)", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
        ]) : nil

        var parts: [Part] = []
        if let workspaceText {
            parts.append(Part(width: ceil(workspaceText.size().width), gapAfter: 4) { x in draw(workspaceText, at: x) })
        }
        parts.append(Part(width: glyphSize.width, gapAfter: shown.isEmpty ? 0 : 5) { x in
            let rect = CGRect(x: x, y: (height - glyphSize.height) / 2,
                              width: glyphSize.width, height: glyphSize.height)
            drawLayout(layout, color: mode.isEmpty ? .labelColor : Theme.ns(\.accent), in: rect)
        })
        for (i, pid) in shown.enumerated() {
            let icon = AppIcons.shared.icon(for: pid)
            parts.append(Part(width: iconSize, gapAfter: i == shown.count - 1 ? 2 : 1) { x in
                icon?.draw(in: CGRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
            })
        }
        if let extraText {
            parts.append(Part(width: ceil(extraText.size().width), gapAfter: 0) { x in draw(extraText, at: x) })
        }
        if parts.last?.gapAfter ?? 0 > 0 { parts[parts.count - 1].gapAfter = 0 }

        let width = parts.reduce(0) { $0 + $1.width + $1.gapAfter }
        let image = NSImage(size: CGSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(x)
                x += part.width + part.gapAfter
            }
            return true
        }
        image.accessibilityDescription = (workspace.map { "Workspace \($0), " } ?? "") + layout.title
            + (mode.isEmpty ? "" : ", \(mode) mode")
        return image
    }

    private static func draw(_ text: NSAttributedString, at x: CGFloat) {
        let size = text.size()
        text.draw(at: CGPoint(x: x, y: (height - size.height) / 2))
    }

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

    private static func drawLayout(_ layout: Layout, color: NSColor, in rect: CGRect) {
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        color.withAlphaComponent(0.85).setStroke()
        outline.stroke()

        let inner = rect.insetBy(dx: 2, dy: 2)
        let gap: CGFloat = 1
        let (count, mains) = panes(layout)
        let frames = layout.frames(count: count,
                                   in: CGRect(origin: .zero, size: inner.size).insetBy(dx: -gap / 2, dy: -gap / 2),
                                   ratio: 0.55, mainCount: mains)?
            .map { frame in
                CGRect(x: inner.minX + frame.minX, y: inner.maxY - frame.maxY, width: frame.width, height: frame.height)
                    .insetBy(dx: gap / 2, dy: gap / 2)
            }
        guard let frames else {
            let back = CGRect(x: inner.minX, y: inner.midY - 1, width: inner.width * 0.6, height: inner.height / 2 + 1)
            let front = CGRect(x: inner.maxX - inner.width * 0.6, y: inner.minY,
                               width: inner.width * 0.6, height: inner.height / 2 + 1)
            color.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: back, xRadius: 1, yRadius: 1).fill()
            color.setFill()
            NSBezierPath(roundedRect: front, xRadius: 1, yRadius: 1).fill()
            return
        }
        for (i, frame) in frames.enumerated().reversed() {
            color.withAlphaComponent(i < mains ? 1 : 0.45).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 1, yRadius: 1).fill()
        }
    }
}
