import AppKit
import CatWMKit
import SwiftUI

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
                    Image(systemName: "xmark.circle.fill").font(Theme.symbol(Theme.Icon.small, .regular))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if !shortcut.isEmpty {
                Kbd(keys: shortcut)
            }
        }
        .padding(.horizontal, Theme.Space.medium)
        .frame(height: 34)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
extension OSearchField {
    static func galleryExample(text: Binding<String>, focus: FocusState<Bool>.Binding) -> some View {
        OSearchField(placeholder: "Search settings", text: text, shortcut: ["⌘", "K"], focus: focus)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.surface.opacity(0.6)))
            .frame(width: 320)
    }
}
#endif

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
            .padding(.horizontal, Theme.Space.medium).frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.focus, lineWidth: focused ? 2 : 0))
            .accessibilityLabel(placeholder)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var textFieldExamples: some View {
        HStack(spacing: Theme.Space.large) {
            OTextField(placeholder: "Text field", text: $model.text)
                .frame(width: 220)
            OTextField(placeholder: "Monospaced", text: $model.text, mono: true)
                .frame(width: 220)
        }
    }
}
#endif
