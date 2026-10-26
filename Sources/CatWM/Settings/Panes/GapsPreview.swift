import AppKit
import SwiftUI

struct GapsPreview: View {
    let config: Config
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
        guard usable.width > 4, usable.height > 4 else { return [] }
        let strip = Strip(columns: [.init([1], width: config.columnWidth), .init([2, 3], width: config.columnWidth)])
        return strip.frames(in: usable, gap: gap).sorted { $0.key < $1.key }.map(\.value)
    }
}
