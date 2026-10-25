import AppKit
import NativeTrafficLight
import SwiftUI

enum TabStripStyle: String, CaseIterable {
    case inset
    case full

    var sideInset: CGFloat { self == .inset ? Theme.Radius.pane : 0 }
    var corner: CGFloat { self == .full ? Theme.Radius.pane : 0 }
    var panelHeight: CGFloat { TabStrip.height + corner }
}

enum TabStrip {
    static let height: CGFloat = Theme.rowHeight
    static let lights: TrafficLights.Buttons = [.close, .minimize]
    static let lightsInset: CGFloat = ((height - TrafficLights.lightDiameter) / 2).rounded()
    static let lead: CGFloat = lightsInset + TrafficLights.size(for: lights).width + Theme.Space.medium
    static let radius: CGFloat = Theme.Radius.large
    static let closeSide: CGFloat = 20
    static let iconSide: CGFloat = 16
    static let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
    static var animated: Bool { WindowManager.shared.config.animate }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var motion: Animation? { animated ? Motion.snap(reduceMotion) : nil }
    static func fade(_ duration: Double) -> Double { animated ? duration : 0 }
}

final class TabStripModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: CGWindowID
        var title: String
        let pid: pid_t
        var badge: Badge?
    }

    @Published var tabs: [Tab] = []
    @Published var style = TabStripStyle.inset
    @Published var active: CGWindowID = 0
    @Published var focused = false
    @Published var hovered: CGWindowID?
    @Published var closeHovered = false
    @Published var dragged: CGWindowID?
    @Published var dragShift: CGFloat = 0
    @Published var lifted = false

    func tabWidth(in width: CGFloat) -> CGFloat { max(0, width - TabStrip.lead) / CGFloat(max(tabs.count, 1)) }

    func slotX(_ index: Int, width: CGFloat) -> CGFloat { TabStrip.lead + CGFloat(index) * tabWidth(in: width) }

    func index(at x: CGFloat, width: CGFloat) -> Int? {
        guard !tabs.isEmpty, x >= TabStrip.lead, tabWidth(in: width) > 0 else { return nil }
        return min(tabs.count - 1, Int(((x - TabStrip.lead) / tabWidth(in: width)).rounded(.down)))
    }

    func closeRect(_ index: Int, width: CGFloat) -> CGRect {
        CGRect(x: slotX(index, width: width) + Theme.Space.small, y: (TabStrip.height - TabStrip.closeSide) / 2,
               width: TabStrip.closeSide, height: TabStrip.closeSide)
    }
}

struct TabStripView: View {
    @ObservedObject var model: TabStripModel

    var body: some View {
        VStack(spacing: 0) {
            bar.frame(height: TabStrip.height)
            if model.style.corner > 0 {
                HStack(spacing: 0) {
                    TabStripCorner(side: model.style.corner, style: model.style)
                    Spacer(minLength: 0)
                    TabStripCorner(side: model.style.corner, style: model.style).scaleEffect(x: -1)
                }
                .frame(height: model.style.corner)
            }
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let tabWidth = model.tabWidth(in: width)
            ZStack(alignment: .topLeading) {
                if let hovered = model.hovered, hovered != model.active, model.dragged == nil,
                   let index = model.tabs.firstIndex(where: { $0.id == hovered }) {
                    Rectangle().fill(Theme.ink.opacity(0.04))
                        .frame(width: tabWidth, height: TabStrip.height)
                        .offset(x: model.slotX(index, width: width))
                }
                if let index = model.tabs.firstIndex(where: { $0.id == model.active }) {
                    Rectangle().fill(Theme.ink.opacity(model.focused ? 0.1 : 0.06))
                        .frame(width: tabWidth, height: TabStrip.height)
                        .offset(x: offset(of: index, id: model.active, width: width))
                        .transaction { if model.dragged == model.active { $0.animation = nil } }
                }
                ForEach(1..<max(model.tabs.count, 1), id: \.self) { index in
                    Rectangle().fill(Theme.hairline)
                        .frame(width: 1, height: TabStrip.height / 2)
                        .offset(x: model.slotX(index, width: width) - 0.5, y: TabStrip.height / 4)
                        .opacity(separated(index) ? 1 : 0)
                }
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                    let dragged = model.dragged == tab.id
                    TabCell(tab: tab, active: tab.id == model.active, focused: model.focused,
                            hovered: model.hovered == tab.id && model.dragged == nil,
                            closeHovered: model.closeHovered)
                        .frame(width: tabWidth, height: TabStrip.height)
                        .offset(x: offset(of: index, id: tab.id, width: width))
                        .opacity(dragged && model.lifted ? 0.55 : 1)
                        .zIndex(dragged ? 1 : 0)
                        .transaction { if dragged { $0.animation = nil } }
                        .transition(.opacity)
                }
            }
        }
        .background { TabStripBackdrop(style: model.style) }
        .clipShape(TabStrip.shape)
        .overlay {
            TabStrip.shape.strokeBorder(Theme.hairline, lineWidth: 1)
                .padding(.bottom, -1)
        }
        .clipped()
        .animation(TabStrip.motion, value: model.tabs.map(\.id))
        .animation(fade(TabStrip.reduceMotion ? Motion.fade : Motion.easeOut), value: model.active)
        .animation(fade(Motion.fade), value: model.focused)
        .animation(fade(Motion.fade), value: model.hovered)
    }

    private func fade(_ animation: Animation) -> Animation? { TabStrip.animated ? animation : nil }

    private func offset(of index: Int, id: CGWindowID, width: CGFloat) -> CGFloat {
        model.slotX(index, width: width) + (model.dragged == id ? model.dragShift : 0)
    }

    private func separated(_ index: Int) -> Bool {
        guard model.dragged == nil, index < model.tabs.count else { return false }
        let lit: Set<CGWindowID> = [model.active, model.hovered ?? 0]
        return !lit.contains(model.tabs[index - 1].id) && !lit.contains(model.tabs[index].id)
    }
}

private struct TabStripBackdrop: View {
    let style: TabStripStyle

    var body: some View {
        ZStack {
            Theme.surface
            if style == .full { Theme.ink.opacity(0.04) }
        }
    }
}

private struct TabStripCorner: View {
    let side: CGFloat
    let style: TabStripStyle

    private var wedge: Path {
        var path = Path()
        path.addRelativeArc(center: CGPoint(x: side, y: side), radius: side,
                            startAngle: .degrees(270), delta: .degrees(-90))
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }

    private var edge: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.5, y: side))
        return path
    }

    var body: some View {
        ZStack {
            TabStripBackdrop(style: style).clipShape(wedge)
            edge.stroke(Theme.hairline, lineWidth: 1)
        }
        .frame(width: side, height: side)
    }
}

private struct TabCell: View {
    let tab: TabStripModel.Tab
    let active: Bool
    let focused: Bool
    let hovered: Bool
    let closeHovered: Bool

    var body: some View {
        ZStack {
            HStack(spacing: Theme.Space.small - Theme.Space.xxs) {
                Image(nsImage: AppIcons.shared.iconOrGeneric(for: tab.pid))
                    .resizable()
                    .frame(width: TabStrip.iconSide, height: TabStrip.iconSide)
                    .opacity(active || hovered ? 1 : 0.7)
                Text(tab.title)
                    .textStyle(.caption).fontWeight(active && focused ? .medium : .regular)
                    .oneLine()
            }
            .padding(.horizontal, TabStrip.closeSide + Theme.Space.small)
            HStack {
                if hovered {
                    Image(systemName: "xmark")
                        .font(Theme.symbol(Theme.Icon.extraSmall, .bold))
                        .frame(width: TabStrip.closeSide, height: TabStrip.closeSide)
                        .background(Circle().fill(closeHovered ? Theme.well : .clear))
                        .accessibilityLabel("Close tab")
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if let badge = tab.badge {
                    CountBadge(badge: badge).transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.horizontal, Theme.Space.small)
            .animation(TabStrip.motion, value: tab.badge)
        }
        .foregroundStyle(active && focused || hovered ? Theme.ink : Theme.inkMuted)
    }
}

#if DEBUG
extension GalleryExamples {
    static let tabStrip = GalleryExample(order: 19) { AnyView(GalleryContent(model: $0).tabStrip) }
}

extension GalleryContent {
    @ViewBuilder var tabStrip: some View {
        block("Tab strip") {
            VStack(alignment: .leading, spacing: Theme.Space.large) {
                ForEach(TabStripStyle.allCases, id: \.self) { style in
                    ForEach([true, false], id: \.self) { focused in
                        ZStack(alignment: .top) {
                            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.pane,
                                                   topTrailingRadius: Theme.Radius.pane, style: .continuous)
                                .fill(Theme.surfaceRaised)
                                .frame(width: 520, height: Theme.controlHeight)
                                .padding(.top, TabStrip.height)
                            TabStripView(model: .example(style: style, focused: focused))
                                .frame(width: 520 - style.sideInset * 2, height: style.panelHeight)
                        }
                        .frame(width: 520, height: TabStrip.height + Theme.controlHeight, alignment: .top)
                    }
                }
            }
        }
    }
}

private extension TabStripModel {
    static func example(style: TabStripStyle, focused: Bool) -> TabStripModel {
        let model = TabStripModel()
        model.style = style
        let pid = ProcessInfo.processInfo.processIdentifier
        model.tabs = ["Notes", "Terminal", "Design review"].enumerated().map { index, title in
            Tab(id: CGWindowID(index + 1), title: title, pid: pid, badge: [.count(3), nil, .dot][index])
        }
        model.active = 1
        model.focused = focused
        model.hovered = focused ? 3 : nil
        return model
    }
}
#endif
