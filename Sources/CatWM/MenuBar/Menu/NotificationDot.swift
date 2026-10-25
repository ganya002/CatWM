import AppKit
import SwiftUI

struct NotificationDot: View {
    var body: some View {
        Circle().fill(Theme.accent).frame(width: 6, height: 6)
            .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 1).padding(-1))
            .accessibilityHidden(true)
    }
}
