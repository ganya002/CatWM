import AppKit
import SwiftUI

struct FeedbackButton: View {
    var body: some View {
        OIconButton(symbol: "ladybug", label: "Send feedback") { Feedback.shared.open() }
            .frame(width: 30)
    }
}
