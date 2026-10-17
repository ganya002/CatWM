import AppKit
import SwiftUI

func animate(_ duration: Double, curve: CAMediaTimingFunction = easeOutBack, label: String = #fileID,
             changes: () -> Void, completion: (() -> Void)? = nil) {
    PerfMonitor.track("ui:" + label, for: duration)
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = duration
        ctx.timingFunction = curve
        ctx.allowsImplicitAnimation = true
        changes()
    }, completionHandler: completion)
}
