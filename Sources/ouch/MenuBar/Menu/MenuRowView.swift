import AppKit
import SwiftUI

struct MenuRowView: View {
    @ObservedObject var model: MenuModel
    let item: MenuItem
    let level: Int
    var crumb: String?

    var body: some View {
        let highlighted = model.highlight[level] == item.id
        let open = model.path.count > level && model.path[level] == item.id
        let muted: Color = Theme.inkMuted
        OMenuRow(highlight: .fixed(highlighted), open: open, danger: item.danger) {
            if item.kind == .sub {
                withAnimation(Motion.easeOut) { model.path = Array(model.path.prefix(level)) + [item.id] }
            } else {
                model.run(item)
            }
        } lead: {
            lead()
        } label: {
            if item.kind == .footer {
                Text("CatWM \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .textStyle(.caption).foregroundStyle(muted).oneLine()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.label).oneLine().layoutPriority(1)
                    if item.dot { NotificationDot() }
                    if let crumb, !crumb.isEmpty {
                        Text(crumb).textStyle(.caption).foregroundStyle(muted).oneLine()
                    } else if let value = item.value {
                        Text(value).font(Theme.body(12.5)).foregroundStyle(muted).oneLine()
                    }
                }
                .layoutPriority(1)
            }
        } trailing: {
            if item.kind == .footer {
                Image(systemName: "power").font(Theme.symbol(Theme.Icon.small)).foregroundStyle(muted)
                Text(item.label).font(Theme.body(12.5)).oneLine()
            }
            if let badge = item.badge {
                Text("\(badge)").font(Theme.body(12, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            if item.kind == .sub && crumb == nil {
                Image(systemName: "chevron.right").font(Theme.symbol(10, .semibold)).foregroundStyle(muted)
            } else if !item.shortcut.isEmpty {
                Text(item.shortcut.joined()).font(Theme.keys(13)).tracking(1).foregroundStyle(muted).oneLine()
                    .fixedSize()
            }
        }
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { if $0 { model.hover(item, level: level) } else { model.unhover(item, level: level) } }
        .background(GeometryReader { geo in
            Color.clear.preference(key: RowFrameKey.self,
                                   value: item.kind == .sub ? [item.id: geo.frame(in: .named("menu"))] : [:])
        })
        .accessibilityLabel(item.label)
        .accessibilityValue(item.value ?? "")
        .accessibilityAddTraits(item.checked ? .isSelected : [])
    }

    @ViewBuilder private func lead() -> some View {
        switch item.kind {
        case .check:
            Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.small, .bold))
                .foregroundStyle(Theme.ink)
                .opacity(item.checked ? 1 : 0)
                .drawOnEffect(isActive: item.checked)
        case .radio:
            Circle().fill(Theme.ink).frame(width: 7, height: 7).opacity(item.checked ? 1 : 0)
        case .footer:
            Color.clear
        default:
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
            }
        }
    }
}
