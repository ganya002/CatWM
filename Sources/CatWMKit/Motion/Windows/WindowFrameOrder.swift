import CoreGraphics

package enum WindowFrameOrder {
    case positionFirst, sizeFirst

    package init(from source: CGRect, to target: CGRect) {
        guard !source.isNull else { self = .sizeFirst; return }
        let bounds = source.union(target)
        func excess(_ frame: CGRect) -> CGFloat {
            let inside = frame.intersection(bounds)
            return frame.width * frame.height - (inside.isNull ? 0 : inside.width * inside.height)
        }
        let moved = CGRect(origin: target.origin, size: source.size)
        let sized = CGRect(origin: source.origin, size: target.size)
        if excess(moved) == excess(sized) {
            self = target.minY < source.minY ? .positionFirst : .sizeFirst
        } else {
            self = excess(moved) < excess(sized) ? .positionFirst : .sizeFirst
        }
    }
}
