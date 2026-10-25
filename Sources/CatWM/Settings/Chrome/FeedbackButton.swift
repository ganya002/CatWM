import AppKit
import SwiftUI

struct FeedbackButton: View {
    var body: some View {
        OIconButton(symbol: "ladybug", label: "Send feedback", tip: true) { Feedback.shared.open() }
            .frame(width: 30)
    }
}
