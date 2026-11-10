import AppKit
import CatWMKit
import CoreText
import SwiftUI

struct LayoutThumbnail: View {
    let layout: Layout
    var count = 4
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let frames = Self.frames(layout, count: count, size: geometry.size)
            let radius = max(1.5, min(geometry.size.width, geometry.size.height) * 0.05)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()).reversed(), id: \.offset) { i, frame in
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(i == 0 ? (selected ? Theme.accent : Theme.thumbMain) : Theme.tint)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
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
        let bounds = CGRect(origin: .zero, size: size)
        return layout.frames(count: count, in: bounds.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)?
            .map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
            ?? [CGRect(x: size.width * 0.06, y: size.height * 0.1,
                       width: size.width * 0.56, height: size.height * 0.56),
                CGRect(x: size.width * 0.38, y: size.height * 0.34,
                       width: size.width * 0.56, height: size.height * 0.56)]
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var thumbnailExamples: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Theme.Space.medium)], alignment: .leading,
                      spacing: Theme.Space.medium) {
                ForEach(Layout.allCases, id: \.self) { layout in
                    VStack(spacing: Theme.Space.extraSmall) {
                        LayoutThumbnail(layout: layout, selected: layout == model.layout).frame(width: 64, height: 40)
                        Text(layout.shortTitle).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    }
                }
            }
    }
}
#endif
