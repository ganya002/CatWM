import AppKit
import CatWMKit
import SwiftUI

struct SortThumb: View {
    let layout: Layout
    let ids: [CGWindowID]
    let lit: CGWindowID?
    var ratio: CGFloat = 0.5
    var mainCount = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frames = Self.frames(layout, ids.count, geo.size, ratio: ratio, mainCount: mainCount)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.well)
                ForEach(Array(ids.enumerated()), id: \.element) { j, id in
                    if j < frames.count {
                        RoundedRectangle(cornerRadius: 3, style: .continuous) // style-ok: a window in a thumbnail
                            .fill(id == lit ? Theme.ink : j == 0 ? Theme.thumbMain : Theme.tint)
                            .frame(width: frames[j].width, height: frames[j].height)
                            .offset(x: frames[j].minX, y: frames[j].minY)
                    }
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .transaction(value: layout) { if let motion { $0.animation = motion } }
        .transaction(value: ids) { if let motion { $0.animation = motion } }
        .accessibilityHidden(true)
    }

    private var motion: Animation? {
        guard let animation = Motion.user else { return nil }
        return reduceMotion ? Motion.fade : animation
    }

    static func frames(_ layout: Layout, _ count: Int, _ size: CGSize, ratio: CGFloat, mainCount: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let scale = size.width / 140
        let inset = 4 * scale, gap = 3 * scale
        let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        if layout == .fullscreen {
            let step = 4 * scale, shrink = CGFloat(min(count - 1, 6)) * step
            return (0..<count).map {
                CGRect(x: rect.minX + CGFloat(min($0, 6)) * step, y: rect.minY + CGFloat(min($0, 6)) * step,
                       width: rect.width - shrink, height: rect.height - shrink)
            }
        }
        if let frames = layout.frames(count: count, in: rect.insetBy(dx: -gap / 2, dy: -gap / 2),
                                      ratio: ratio, mainCount: mainCount) {
            return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
        }
        return (0..<count).map {
            CGRect(x: rect.minX + CGFloat(min($0, 6)) * 6 * scale, y: rect.minY + CGFloat(min($0, 6)) * 6 * scale,
                   width: rect.width * 0.6, height: rect.height * 0.6)
        }
    }
}
