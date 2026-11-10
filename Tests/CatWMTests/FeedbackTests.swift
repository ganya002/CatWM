@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct FeedbackTests {
    @Test @MainActor func sendingKeepsAnEditedDraftOpen() {
        let feedback = Feedback()
        feedback.open()
        feedback.text = "A new draft"
        feedback.sending = true
        feedback.finishSend(body: "Sent report", success: true)
        #expect(feedback.isOpen)
        #expect(feedback.text == "A new draft")
        #expect(!feedback.sending)
    }
}
