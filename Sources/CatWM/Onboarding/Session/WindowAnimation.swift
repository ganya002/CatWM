import AppKit
import SwiftUI

func animate(_ duration: Double, curve: CAMediaTimingFunction = easeOutBack, label: String = #fileID,
             changes: () -> Void, completion: (() -> Void)? = nil) {
    PerfMonitor.shared.track("ui:" + label, for: duration)
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = duration
        ctx.timingFunction = curve
        ctx.allowsImplicitAnimation = true
        changes()
    }, completionHandler: completion)
}

let easeOutBack = Motion.Curve.settle

extension NSWindow.Level {
    static func above(_ level: NSWindow.Level, _ offset: Int) -> NSWindow.Level {
        NSWindow.Level(rawValue: level.rawValue + offset)
    }
}
