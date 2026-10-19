import AppKit
import SwiftUI

struct SortLayoutGlyph: View {
    let layout: Layout

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 1, dy: 0.5)
            let frames = layout.frames(count: paneCount, in: bounds.insetBy(dx: -0.75, dy: -0.75),
                                       ratio: 0.5, mainCount: 1)?
                .map { $0.insetBy(dx: 0.75, dy: 0.75) }
                ?? [CGRect(x: 1, y: 1, width: 9, height: 8), CGRect(x: 5, y: 4, width: 10, height: 9)]
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 1.4, style: .continuous) // style-ok: a glyph-size drawing
                        .frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .opacity(0.8)
        .accessibilityHidden(true)
    }

    private var paneCount: Int {
        switch layout {
        case .fullscreen: 1
        case .bsp: 4
        case .twoPane, .twoPaneRight: 2
        default: 3
        }
    }
}
