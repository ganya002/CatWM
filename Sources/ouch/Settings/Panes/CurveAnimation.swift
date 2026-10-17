import AppKit
import SwiftUI

struct CurveAnimation: CustomAnimation {
    let curve: AnimationCurve
    let bounce: Double
    let duration: Double

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: curve.progress(time / duration, bounce: bounce))
    }
}
