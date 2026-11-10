import CatWMKit
import SwiftUI

struct CountBadge: View {
    let badge: Badge
    static let side: CGFloat = 16
    static let dot: CGFloat = 8

    var body: some View {
        Group {
            if let text = badge.text {
                Text(text)
                    .font(Theme.body(10.5, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.onBadge)
                    .padding(.horizontal, Theme.Space.extraSmall)
                    .frame(minWidth: Self.side, minHeight: Self.side)
                    .background(Capsule().fill(Theme.badge))
                    .fixedSize()
            } else {
                Circle().fill(Theme.badge).frame(width: Self.dot, height: Self.dot)
            }
        }
        .accessibilityLabel(badge.text.map { "\($0) unread" } ?? "Unread")
    }
}
