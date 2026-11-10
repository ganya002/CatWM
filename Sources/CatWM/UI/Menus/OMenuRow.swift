import AppKit
import CatWMKit
import SwiftUI

struct OMenuRow<Lead: View, Label: View, Trailing: View>: View {
    var highlight = MenuRowHighlight.followsHover
    var open = false
    var danger = false
    let action: () -> Void
    @ViewBuilder var lead: Lead
    @ViewBuilder var label: Label
    @ViewBuilder var trailing: Trailing
    @AccessibilityFocusState private var voiceOverFocus: Bool
    @Environment(\.isEnabled) private var enabled

    init(highlight: MenuRowHighlight = .followsHover, open: Bool = false, danger: Bool = false,
         action: @escaping () -> Void, @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label,
         @ViewBuilder trailing: () -> Trailing) {
        self.highlight = highlight; self.open = open; self.danger = danger; self.action = action
        self.lead = lead(); self.label = label(); self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.medium) {
                if Lead.self != EmptyView.self { lead.frame(width: 16) }
                label
                Spacer(minLength: 6)
                trailing
            }
            .font(Theme.body(13.5))
            .foregroundStyle(!enabled ? Theme.inkFaint : danger ? Theme.danger : Theme.ink)
        }
        .buttonStyle(OMenuRowStyle(highlight: highlight, open: open, danger: danger))
        .accessibilityFocused($voiceOverFocus)
        .onChange(of: highlight) { _, new in
            if new == .fixed(true) { voiceOverFocus = true }
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let menus = GalleryExample(order: 11) { AnyView(GalleryContent(model: $0).menus) }
}

extension GalleryContent {
    @ViewBuilder var menus: some View {
        block("Menu rows") {
            VStack(spacing: 0) {
                OMenuRow(action: {}, lead: { EmptyView() }, label: { Text("Settings…") },
                         trailing: { Text("⌘,").foregroundStyle(Theme.inkMuted) })
                OMenuRow(highlight: .fixed(true), action: {}, lead: { EmptyView() },
                         label: { Text("Highlighted row") })
                OMenuRow(open: true, action: {}, lead: { EmptyView() },
                         label: { Text("Layout") },
                         trailing: { Image(systemName: "chevron.right").foregroundStyle(Theme.inkMuted) })
                OMenuRow(action: {}, lead: { EmptyView() }, label: { Text("Disabled row") }).disabled(true)
                OMenuRow(danger: true, action: {}, lead: { EmptyView() }, label: { Text("Quit CatWM") })
            }
            .frame(width: Theme.menuWidth)
            .padding(Theme.Space.extraSmall + Theme.Space.xxs)
            .surface(.medium)
            HStack(spacing: Theme.Space.medium) {
                menuPickerExample
                menuButtonExample
            }
        }
    }
}
#endif

extension OMenuRow where Trailing == EmptyView {
    init(highlight: MenuRowHighlight = .followsHover, open: Bool = false, danger: Bool = false,
         action: @escaping () -> Void, @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label) {
        self.init(highlight: highlight, open: open, danger: danger, action: action, lead: lead, label: label) {
            EmptyView()
        }
    }
}

extension OMenuRow where Lead == EmptyView {
    init(highlight: MenuRowHighlight = .followsHover, open: Bool = false, danger: Bool = false,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.init(highlight: highlight, open: open, danger: danger, action: action, lead: { EmptyView() },
                  label: label, trailing: trailing)
    }
}

enum MenuRowHighlight: Equatable {
    case followsHover
    case fixed(Bool)

    func isLit(hovering: Bool) -> Bool {
        switch self {
        case .followsHover: hovering
        case let .fixed(lit): lit
        }
    }
}

struct OMenuRowStyle: ButtonStyle {
    static let inset: CGFloat = 10
    var highlight = MenuRowHighlight.followsHover
    var open = false
    var danger = false
    var bare = false

    func makeBody(configuration: Configuration) -> some View { OMenuRowBody(configuration: configuration, style: self) }
}

struct OMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OMenuRowStyle
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let lit = enabled && style.highlight.isLit(hovering: hover.isOn)
        let fill: Color = configuration.isPressed ? Theme.wellHover
            : lit ? (style.danger ? Theme.dangerSoft : Theme.hover)
            : style.open ? Theme.wellHover : .clear
        Group {
            if style.bare {
                configuration.label
            } else {
                configuration.label
                    .padding(.horizontal, OMenuRowStyle.inset)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, maxHeight: Theme.rowHeight,
                           alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
    }
}
