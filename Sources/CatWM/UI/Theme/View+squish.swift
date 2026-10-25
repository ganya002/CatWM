import AppKit
import CoreText
import SwiftUI

extension View {
    func squish<T: Equatable>(
        on trigger: T, when: Bool = true, delay: Double = 0, anchor: UnitPoint = .bottom
    ) -> some View {
        modifier(Squish(trigger: trigger, delay: delay, anchor: anchor, enabled: when))
    }
}
