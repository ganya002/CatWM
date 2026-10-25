import AppKit
import QuartzCore

func measure(_ body: () -> Void) -> Double {
    let start = CACurrentMediaTime()
    body()
    return CACurrentMediaTime() - start
}
