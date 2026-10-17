import AppKit
import CoreText
import SwiftUI

struct LayoutThumbnail: View {
    let layout: Layout
    var count = 4
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let frames = Self.frames(layout, count: count, size: g.size)
            let r = max(1.5, min(g.size.width, g.size.height) * 0.05)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()).reversed(), id: \.offset) { i, f in
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(i == 0 ? (selected ? Theme.accent : Theme.thumbMain) : Theme.tint)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .animation(Motion.snap(reduceMotion), value: layout)
        .animation(Motion.fadeMedium, value: selected)
        .accessibilityHidden(true)
    }

    private static func frames(_ layout: Layout, count: Int, size: CGSize) -> [CGRect] {
        let gap = max(1.5, size.width * 0.035)
        let r = CGRect(origin: .zero, size: size)
        return layout.frames(count: count, in: r.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)?
            .map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
            ?? [CGRect(x: size.width * 0.06, y: size.height * 0.1, width: size.width * 0.56, height: size.height * 0.56),
                CGRect(x: size.width * 0.38, y: size.height * 0.34, width: size.width * 0.56, height: size.height * 0.56)]
    }
}
