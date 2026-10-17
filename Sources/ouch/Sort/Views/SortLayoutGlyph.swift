import AppKit
import SwiftUI

struct SortLayoutGlyph: View {
    let layout: Layout

    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size).insetBy(dx: 1, dy: 0.5)
            let count = layout == .fullscreen ? 1 : layout == .bsp ? 4 : layout == .twoPane || layout == .twoPaneRight ? 2 : 3
            let frames = layout.frames(count: count, in: r.insetBy(dx: -0.75, dy: -0.75), ratio: 0.5, mainCount: 1)?
                .map { $0.insetBy(dx: 0.75, dy: 0.75) }
                ?? [CGRect(x: 1, y: 1, width: 9, height: 8), CGRect(x: 5, y: 4, width: 10, height: 9)]
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                    RoundedRectangle(cornerRadius: 1.4, style: .continuous).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY) // style-ok: a glyph-size drawing
                }
            }
        }
        .opacity(0.8)
        .accessibilityHidden(true)
    }
}
