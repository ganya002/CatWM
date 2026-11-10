import CoreGraphics

package struct SplitDivider: Equatable {
    package static let ratioRange: ClosedRange<CGFloat> = 0.1...0.9

    package let vertical: Bool
    package let fromStart: Bool
    package let frame: CGRect

    package var position: CGFloat { vertical ? frame.midX : frame.midY }

    package static func mains(_ layout: Layout, mainCount: Int, count: Int) -> Int {
        [.bsp, .twoPane, .twoPaneRight].contains(layout) ? 1 : max(1, min(mainCount, count))
    }

    package init?(layout: Layout, slots: [CGRect], mainCount: Int, in rect: CGRect) {
        guard var axis = layout.ratioAxis else { return nil }
        if layout == .bsp { axis = (rect.width >= rect.height, true) }
        let mains = Self.mains(layout, mainCount: mainCount, count: slots.count)
        guard slots.count > mains else { return nil }
        let main = slots[..<mains].reduce(CGRect.null) { $0.union($1) }
        let rest = slots[mains...].reduce(CGRect.null) { $0.union($1) }
        let (low, high) = switch (axis.horizontal, axis.fromStart) {
        case (true, true): (main.maxX, rest.minX)
        case (true, false): (rest.maxX, main.minX)
        case (false, true): (main.maxY, rest.minY)
        case (false, false): (rest.maxY, main.minY)
        }
        let thickness = max(0, high - low), center = (low + high) / 2
        vertical = axis.horizontal
        fromStart = axis.fromStart
        frame = vertical
            ? CGRect(x: center - thickness / 2, y: rect.minY, width: thickness, height: rect.height)
            : CGRect(x: rect.minX, y: center - thickness / 2, width: rect.width, height: thickness)
    }

    package func ratio(at position: CGFloat, in rect: CGRect, gap: CGFloat) -> CGFloat {
        let start = vertical ? rect.minX : rect.minY, length = (vertical ? rect.width : rect.height) + gap
        guard length > 0 else { return 0.5 }
        let main = fromStart ? position - start + gap / 2 : start + length - gap / 2 - position
        return min(Self.ratioRange.upperBound, max(Self.ratioRange.lowerBound, main / length))
    }
}
