import AppKit
import SwiftUI

struct SortThumb: View {
    let ids: [CGWindowID]
    let lit: CGWindowID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frames = Self.frames(ids.count, geo.size)
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
        .transaction(value: ids) { if let motion { $0.animation = motion } }
        .accessibilityHidden(true)
    }

    private var motion: Animation? {
        guard let animation = PanelMotion.windowAnimation else { return nil }
        return reduceMotion ? Motion.fade : animation
    }

    static func frames(_ count: Int, _ size: CGSize) -> [CGRect] {
        guard count > 0 else { return [] }
        let scale = size.width / 140
        let inset = 4 * scale, gap = 3 * scale
        let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let width = (rect.width + gap) / CGFloat(min(count, 3))
        return (0..<count).map {
            CGRect(x: rect.minX + CGFloat($0) * width, y: rect.minY, width: width - gap, height: rect.height)
        }
    }
}
