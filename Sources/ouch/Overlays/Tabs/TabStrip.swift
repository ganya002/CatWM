import AppKit
import SwiftUI

enum TabStrip {
    static let height: CGFloat = Theme.controlHeight + Theme.Space.small
    static let overlap: CGFloat = Theme.Radius.pane
    static let radius: CGFloat = Theme.Radius.pane
    static let spacing: CGFloat = Theme.Space.xxs
    static let lead: CGFloat = Theme.Space.xxl
    static let closeSide: CGFloat = 20
    static let iconSide: CGFloat = 16
    static let lightSide: CGFloat = 14
    static let tabRadius: CGFloat = Theme.Radius.medium
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
    @Published var lightHovered = false
    @Published var dragged: CGWindowID?
    @Published var dragShift: CGFloat = 0
    @Published var lifted = false

    func tabWidth(in width: CGFloat) -> CGFloat {
        let count = CGFloat(max(tabs.count, 1))
        return max(0, (width - TabStrip.lead - TabStrip.spacing * (count - 1)) / count)
    }

    func slotX(_ index: Int, width: CGFloat) -> CGFloat {
        TabStrip.lead + CGFloat(index) * (tabWidth(in: width) + TabStrip.spacing)
    }

    func onLight(_ x: CGFloat) -> Bool { x < TabStrip.lead - TabStrip.spacing / 2 }

    func index(at x: CGFloat, width: CGFloat) -> Int? {
        guard !tabs.isEmpty, !onLight(x) else { return nil }
        let step = tabWidth(in: width) + TabStrip.spacing
        guard step > 0 else { return nil }
        return min(tabs.count - 1, max(0, Int(((x - TabStrip.lead + TabStrip.spacing / 2) / step).rounded(.down))))
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
                TrafficLight(hovered: model.lightHovered)
                    .frame(width: TabStrip.lead, height: TabStrip.height)
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, _ in
                    if index > 0, !beside(index) {
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
                        .frame(width: model.tabWidth(in: width), height: TabStrip.height)
                        .offset(x: model.slotX(index, width: width) + (dragged ? model.dragShift : 0))
                        .zIndex(dragged ? 1 : 0)
                        .transaction { if dragged { $0.animation = nil } }
                        .transition(.opacity)
                }
            }
        }
        .background(Theme.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: TabStrip.radius, topTrailingRadius: TabStrip.radius,
                                          style: .continuous))
        .animation(Motion.snap, value: model.tabs.map(\.id))
        .animation(Motion.fade, value: model.active)
        .animation(Motion.fade, value: model.focused)
        .animation(Motion.fade, value: model.hovered)
        .animation(Motion.fade, value: model.lightHovered)
    }

    private func beside(_ index: Int) -> Bool {
        let lit = [model.active, model.dragged].compactMap(\.self)
        return lit.contains(model.tabs[index].id) || lit.contains(model.tabs[index - 1].id)
    }
}

private struct TrafficLight: View {
    let hovered: Bool

    var body: some View {
        ZStack {
            Circle().fill(Self.red)
            Circle().strokeBorder(Self.rim, lineWidth: 0.5)
            if hovered {
                Image(systemName: "xmark")
                    .font(Theme.symbol(Theme.Icon.extraSmall - 2, .bold))
                    .foregroundStyle(Self.glyph)
            }
        }
        .frame(width: TabStrip.lightSide, height: TabStrip.lightSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help("Close all tabs")
    }

    private static let red = Theme.rgb(0xFF5F57)
    private static let rim = Theme.rgb(0xE2463F)
    private static let glyph = Theme.rgb(0x4D0000)
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
        .foregroundStyle(active && focused || hovered ? Theme.ink : Theme.inkMuted)
        .background(UnevenRoundedRectangle(topLeadingRadius: TabStrip.tabRadius, topTrailingRadius: TabStrip.tabRadius,
                                           style: .continuous).fill(fill))
        .opacity(lifted ? 0.55 : 1)
        .help(tab.title)
    }

    private var fill: Color {
        guard active || lifted else { return .clear }
        return focused ? Theme.hover : Theme.surfaceRaised
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
