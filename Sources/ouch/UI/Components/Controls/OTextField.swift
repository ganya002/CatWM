import AppKit
import SwiftUI

struct OTextField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var onSubmit: () -> Void = {}
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint))
            .textFieldStyle(.plain)
            .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
            .font(mono ? Theme.mono(12, .regular) : Theme.body(13))
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10).frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.focus, lineWidth: focused ? 2 : 0))
            .accessibilityLabel(placeholder)
    }
}
