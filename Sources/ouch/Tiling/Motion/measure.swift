import AppKit
import QuartzCore

func measure(_ f: () -> Void) -> Double {
    let t = CACurrentMediaTime()
    f()
    return CACurrentMediaTime() - t
}
