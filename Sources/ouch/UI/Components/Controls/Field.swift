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

struct OSearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcut: [String] = []
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink)
                .focused(focus)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(Theme.symbol(Theme.Icon.sm, .regular)).foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if !shortcut.isEmpty {
                Kbd(keys: shortcut)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .accessibilityElement(children: .contain)
    }
}
