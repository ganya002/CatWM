import AppKit
import CatWMKit
import SwiftUI

struct FeedbackSheet: View {
    @ObservedObject var feedback: Feedback
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.medium) {
            Text("Send feedback").textStyle(.title).oneLine()
            editor
            Text(disclosure)
                .textStyle(.caption).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                OButton("Cancel", variant: .ghost) { feedback.close() }.keyboardShortcut(.cancelAction)
                OButton(sendTitle, variant: .primary, shortcut: feedback.sending ? [] : ["⌘", "↩"]) { feedback.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!feedback.canSend)
            }
            .padding(.top, 4)
        }
        .padding(24).frame(width: 440)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
        .onAppear { focused = true }
    }

    private var disclosure: String {
        "This includes your description, CatWM's recent logs, your config and your Mac's setup. "
            + "We use these to fix problems and improve CatWM."
    }

    private var sendTitle: String {
        if feedback.sending { return "Sending…" }
        return feedback.failed ? "Try again" : "Send"
    }

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return TextEditor(text: $feedback.text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .onKeyPress(.tab) {
                let window = NSApp.keyWindow
                if NSEvent.modifierFlags.contains(.shift) {
                    window?.selectPreviousKeyView(nil)
                } else {
                    window?.selectNextKeyView(nil)
                }
                return .handled
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(height: 120)
            .background(shape.fill(Theme.well))
            .overlay(alignment: .topLeading) {
                if feedback.text.isEmpty {
                    Text("Describe the issue or idea")
                        .font(Theme.body(13)).foregroundStyle(Theme.inkFaint).oneLine()
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Feedback")
    }
}
