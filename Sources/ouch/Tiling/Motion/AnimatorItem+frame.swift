import AppKit
import QuartzCore

extension Animator.Item {
    func frame(at now: CFTimeInterval) -> CGRect {
        let t = min(1, max(0, (now - start) / duration))
        let e = CGFloat(curve.progress(t, bounce: bounce))
        let to = move.to
        return CGRect(x: from.minX + (to.minX - from.minX) * e,
                      y: from.minY + (to.minY - from.minY) * e,
                      width: max(1, from.width + (to.width - from.width) * e),
                      height: max(1, from.height + (to.height - from.height) * e)).pixelAligned
    }
}
