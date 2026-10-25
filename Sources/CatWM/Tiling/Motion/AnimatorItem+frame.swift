import AppKit
import QuartzCore

extension Animator.Item {
    func frame(at now: CFTimeInterval) -> CGRect {
        let time = min(1, max(0, (now - start) / duration))
        let eased = CGFloat(curve.progress(time, bounce: bounce))
        let target = move.target
        return CGRect(x: from.minX + (target.minX - from.minX) * eased,
                      y: from.minY + (target.minY - from.minY) * eased,
                      width: max(1, from.width + (target.width - from.width) * eased),
                      height: max(1, from.height + (target.height - from.height) * eased)).pixelAligned
    }
}
