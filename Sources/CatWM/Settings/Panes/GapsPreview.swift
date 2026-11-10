import AppKit
import CatWMKit
import SwiftUI

struct GapsPreview: View {
    let config: Config
    let layout: Layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let wallpaper = LinearGradient(colors: [Theme.accentSoft, Theme.tint],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let full = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let menuBar = (screen.map { $0.frame.maxY - $0.visibleFrame.maxY }) ?? 24
        let dock = (screen.map { $0.visibleFrame.minY - $0.frame.minY }) ?? 0
        GeometryReader { geo in
            let scale = min(geo.size.width / full.width, geo.size.height / full.height)
            let width = full.width * scale, height = full.height * scale
            let bar = config.ignoreMenuBar ? 0 : menuBar * scale
            let frames = windows(in: CGRect(x: 0, y: bar, width: width, height: height - bar - dock * scale),
                                 scale: scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Self.wallpaper)
                Rectangle().fill(Theme.ink.opacity(0.1)).frame(width: width, height: menuBar * scale)
                    .opacity(config.ignoreMenuBar ? 0 : 1)
                ForEach(Array(frames.enumerated()), id: \.offset) { i, frame in
                    RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
                        .fill(i == 0 ? Theme.accent : Theme.thumbMain)
                        .frame(width: max(frame.width, 0), height: max(frame.height, 0))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(Motion.snap(reduceMotion), value: geometry)
        }
        .accessibilityHidden(true)
    }

    private var geometry: [CGFloat] {
        [config.paddingTop, config.paddingBottom, config.paddingLeft, config.paddingRight, config.windowMarginSize,
         config.windowMargins ? 1 : 0, config.ignoreMenuBar ? 1 : 0]
    }

    private func windows(in area: CGRect, scale: CGFloat) -> [CGRect] {
        let usable = CGRect(x: area.minX + config.paddingLeft * scale, y: area.minY + config.paddingTop * scale,
                            width: area.width - (config.paddingLeft + config.paddingRight) * scale,
                            height: area.height - (config.paddingTop + config.paddingBottom) * scale)
        let gap = (config.windowMargins ? config.windowMarginSize : 0) * scale
        guard usable.width > 4, usable.height > 4,
              let frames = layout.frames(count: 3, in: usable.insetBy(dx: -gap / 2, dy: -gap / 2),
                                         ratio: 0.5, mainCount: 1)
        else { return [] }
        return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
    }
}
