import AppKit
import CoreText
import SwiftUI

/// Fonts, colours and small controls shared by the Settings window, HUD and menu bar.
enum Theme {
    // MARK: Fonts

    /// Text uses Apple's system fonts (San Francisco, SF Mono). Only Dela Gothic One (OFL; logo and
    /// welcome title) ships in Contents/Resources/Fonts.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let fonts = urls.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    private static let hasDela = NSFont(name: "DelaGothicOne-Regular", size: 12) != nil

    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Pane titles, card headings and HUD text: plain bold body face.
    static func heading(_ size: CGFloat) -> Font { body(size, .bold) }

    /// Dela Gothic One, reserved for the few moments that deserve emphasis: the logo and the welcome title.
    static func display(_ size: CGFloat) -> Font {
        hasDela ? .custom("DelaGothicOne-Regular", size: size) : body(size, .bold)
    }

    static func nsHeading(_ size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }
    static func nsMono(_ size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Colours (system semantic colours, so light/dark, Increase Contrast and accent colour all follow macOS)

    static let window = Color(nsColor: .windowBackgroundColor)
    static let statusBar = Color(nsColor: .windowBackgroundColor)
    /// Raised controls: chips, keycaps.
    static let control = Color(nsColor: .controlColor)
    /// Grouped-form box fill, as in System Settings.
    static let card = Color(nsColor: .quaternarySystemFill)
    static let hairline = Color(nsColor: .separatorColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
}

// MARK: - Layout pieces

/// Grouped box: rounded tint with a hairline, and a separator between each child view.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(Separated()) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }

    private struct Separated: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    child.overlay(alignment: .top) {
                        if child.id != children.first?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
            }
        }
    }
}

/// Section title above a card, with an optional footnote below it.
struct Block<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(Theme.body(13, .semibold)).foregroundStyle(.primary)
                    .padding(.leading, 2).padding(.bottom, 6)
            }
            content
            if let footer {
                Text(footer).font(Theme.body(11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2).padding(.top, 6)
            }
        }
    }
}

/// One line in a card: label on the left, control on the right.
struct Row<Label: View, Control: View>: View {
    var vertical: CGFloat = 9
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, vertical)
    }
}

extension Row where Label == Text {
    init(_ title: String, vertical: CGFloat = 9, @ViewBuilder control: () -> Control) {
        self.init(vertical: vertical, label: { Text(title) }, control: control)
    }
}

/// Title with a smaller grey explanation underneath.
struct TitleDetail: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(Theme.body(11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Switch row; dims its label when disabled, like System Settings.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Row {
            Group { if let detail { TitleDetail(title: title, detail: detail) } else { Text(title) } }
                .opacity(enabled ? 1 : 0.4)
        } control: {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

// MARK: - Controls (native AppKit-backed controls, so focus, keyboard and VoiceOver all work)

/// Segmented control.
struct Segmented<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Pop-up button. `bordered: false` shows just the value and the ⇕ arrows, as in the design.
struct PopUp<T: Hashable>: View {
    /// Spoken by VoiceOver; not shown.
    let title: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var bordered = false

    var body: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        if bordered { picker } else { picker.buttonStyle(.borderless) }
    }
}

/// Grey circle with a white minus, used to delete list rows.
struct RemoveButton: View {
    let help: String
    let action: () -> Void
    private final class Hover: ObservableObject { @Published var on = false }
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            Circle().fill(Color.primary.opacity(hover.on ? 0.45 : 0.3))
                .frame(width: 16, height: 16)
                .overlay(Capsule().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 8, height: 2))
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Rounded gradient square holding a white glyph (sidebar and hero icons).
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }
}

/// White keycaps for a shortcut.
struct Keycaps: View {
    let caps: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, c in
                Text(c)
                    .font(Theme.body(12, .medium))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.control))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3)))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            }
        }
    }
}
