import AppKit
import SwiftUI

struct SortThumb: View {
    let layout: Layout
    let ids: [CGWindowID]
    let lit: CGWindowID?
    var ratio: CGFloat = 0.5
    var mainCount = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let frames = Self.frames(layout, ids.count, g.size, ratio: ratio, mainCount: mainCount)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well)
                ForEach(Array(ids.enumerated()), id: \.element) { j, id in
                    if j < frames.count {
                        RoundedRectangle(cornerRadius: 3, style: .continuous) // style-ok: a window in a thumbnail
                            .fill(id == lit ? Theme.accent : j == 0 ? Theme.thumbMain : Theme.tint)
                            .frame(width: frames[j].width, height: frames[j].height)
                            .offset(x: frames[j].minX, y: frames[j].minY)
                    }
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .animation(Motion.snap(reduceMotion), value: layout)
        .animation(Motion.snap(reduceMotion), value: ids)
        .accessibilityHidden(true)
    }

    static func frames(_ layout: Layout, _ n: Int, _ size: CGSize, ratio: CGFloat, mainCount: Int) -> [CGRect] {
        guard n > 0 else { return [] }
        let k = size.width / 140
        let inset = 4 * k, gap = 3 * k
        let r = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        if layout == .fullscreen {
            let step = 4 * k, shrink = CGFloat(min(n - 1, 6)) * step
            return (0..<n).map { CGRect(x: r.minX + CGFloat(min($0, 6)) * step, y: r.minY + CGFloat(min($0, 6)) * step,
                                        width: r.width - shrink, height: r.height - shrink) }
        }
        if let f = layout.frames(count: n, in: r.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: ratio, mainCount: mainCount) {
            return f.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
        }
        return (0..<n).map { CGRect(x: r.minX + CGFloat(min($0, 6)) * 6 * k, y: r.minY + CGFloat(min($0, 6)) * 6 * k,
                                    width: r.width * 0.6, height: r.height * 0.6) }
    }
}
