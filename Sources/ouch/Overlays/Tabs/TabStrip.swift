import AppKit
import SwiftUI

enum TabStrip {
    static let height: CGFloat = Theme.controlHeight + Theme.Space.extraSmall
    static let overlap: CGFloat = Theme.Radius.pane
    static let radius: CGFloat = Theme.Radius.pane
    static let padding: CGFloat = Theme.Space.extraSmall
    static let spacing: CGFloat = Theme.Space.xxs
    static let closeSide: CGFloat = 16
    static let iconSide: CGFloat = 16
}

final class TabStripModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: CGWindowID
        var title: String
        let pid: pid_t
    }

    @Published var tabs: [Tab] = []
    @Published var active: CGWindowID = 0
    @Published var focused = false
    @Published var hovered: CGWindowID?
    @Published var closeHovered = false
    @Published var dragged: CGWindowID?
    @Published var dragShift: CGFloat = 0
    @Published var lifted = false

    func tabWidth(in width: CGFloat) -> CGFloat {
        let count = CGFloat(max(tabs.count, 1))
        return max(0, (width - TabStrip.padding * 2 - TabStrip.spacing * (count - 1)) / count)
    }

    func slotX(_ index: Int, width: CGFloat) -> CGFloat {
        TabStrip.padding + CGFloat(index) * (tabWidth(in: width) + TabStrip.spacing)
    }

    func index(at x: CGFloat, width: CGFloat) -> Int? {
        guard !tabs.isEmpty else { return nil }
        let step = tabWidth(in: width) + TabStrip.spacing
        guard step > 0 else { return nil }
        return min(tabs.count - 1, max(0, Int(((x - TabStrip.padding) / step).rounded(.down))))
    }

    func closeRect(_ index: Int, width: CGFloat) -> CGRect {
        let right = slotX(index, width: width) + tabWidth(in: width) - Theme.Space.extraSmall
        return CGRect(x: right - TabStrip.closeSide, y: (TabStrip.height - TabStrip.closeSide) / 2,
                      width: TabStrip.closeSide, height: TabStrip.closeSide)
    }
}

struct TabStripView: View {
    @ObservedObject var model: TabStripModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, _ in
                    if index > 0, !lit(index), !lit(index - 1) {
                        Rectangle().fill(Theme.hairline)
                            .frame(width: 1, height: TabStrip.iconSide)
                            .offset(x: model.slotX(index, width: width) - TabStrip.spacing / 2 - 0.5,
                                    y: (TabStrip.height - TabStrip.iconSide) / 2)
                    }
                }
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                    let dragged = model.dragged == tab.id
                    TabCell(tab: tab, active: tab.id == model.active, focused: model.focused,
                            hovered: model.hovered == tab.id && model.dragged == nil,
                            closeHovered: model.closeHovered, lifted: dragged && model.lifted)
                        .frame(width: model.tabWidth(in: width), height: TabStrip.height - TabStrip.padding * 2)
                        .offset(x: model.slotX(index, width: width) + (dragged ? model.dragShift : 0),
                                y: TabStrip.padding)
                        .zIndex(dragged ? 1 : 0)
                        .transaction { if dragged { $0.animation = nil } }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .background(VisualBlur(radius: TabStrip.radius, material: .titlebar))
        .animation(Motion.snap, value: model.tabs.map(\.id))
        .animation(Motion.fade, value: model.active)
        .animation(Motion.fade, value: model.focused)
        .animation(Motion.fade, value: model.hovered)
    }

    private func lit(_ index: Int) -> Bool {
        let id = model.tabs[index].id
        return id == model.active || (id == model.hovered && model.dragged == nil) || id == model.dragged
    }
}

private struct TabCell: View {
    let tab: TabStripModel.Tab
    let active: Bool
    let focused: Bool
    let hovered: Bool
    let closeHovered: Bool
    let lifted: Bool

    var body: some View {
        ZStack {
            HStack(spacing: Theme.Space.small - Theme.Space.xxs) {
                Image(nsImage: AppIcons.icon(for: tab.pid))
                    .resizable()
                    .frame(width: TabStrip.iconSide, height: TabStrip.iconSide)
                    .opacity(active || hovered ? 1 : 0.7)
                Text(tab.title)
                    .font(Theme.body(12, active && focused ? .medium : .regular))
                    .oneLine()
            }
            .padding(.horizontal, TabStrip.closeSide + Theme.Space.small)
            HStack {
                Spacer(minLength: 0)
                if hovered {
                    Image(systemName: "xmark")
                        .font(Theme.symbol(Theme.Icon.extraSmall, .bold))
                        .frame(width: TabStrip.closeSide, height: TabStrip.closeSide)
                        .background(Circle().fill(closeHovered ? Theme.hover : .clear))
                        .transition(.opacity)
                }
            }
            .padding(.trailing, Theme.Space.extraSmall)
        }
        .foregroundStyle(active && focused ? Theme.ink : Theme.inkMuted)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(fill))
        .opacity(lifted ? 0.55 : 1)
        .scaleEffect(lifted ? 0.96 : 1)
        .help(tab.title)
    }

    private var fill: Color {
        if active { return focused ? Theme.well : Theme.well.opacity(0.6) }
        return hovered ? Theme.well.opacity(0.5) : .clear
    }
}

enum AppIcons {
    private static var cache: [pid_t: NSImage] = [:]

    static func icon(for pid: pid_t) -> NSImage {
        if let cached = cache[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
        cache[pid] = icon
        return icon
    }
}
