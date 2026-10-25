import AppKit
import NativeTrafficLight
import SwiftUI

enum TabStrip {
    static let height: CGFloat = Theme.rowHeight
    static let lights: TrafficLights.Buttons = [.close, .minimize]
    static let lightsInset: CGFloat = ((height - TrafficLights.lightDiameter) / 2).rounded()
    static let lead: CGFloat = 0
    static let trail: CGFloat = lightsInset + TrafficLights.size(for: lights).width + Theme.Space.medium
    static let radius: CGFloat = Theme.Radius.large
    static let corner: CGFloat = Theme.Radius.pane
    static let panelHeight: CGFloat = height + corner
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
    }

    @Published var tabs: [Tab] = []
    @Published var active: CGWindowID = 0
    @Published var focused = false
    @Published var hovered: CGWindowID?
    @Published var closeHovered = false
    @Published var dragged: CGWindowID?
    @Published var dragShift: CGFloat = 0
    @Published var lifted = false

    func tabWidth(in width: CGFloat) -> CGFloat { span(width) / CGFloat(max(tabs.count, 1)) }

    func span(_ width: CGFloat) -> CGFloat { max(0, width - TabStrip.lead - TabStrip.trail) }

    func slotX(_ index: Int, width: CGFloat) -> CGFloat { TabStrip.lead + CGFloat(index) * tabWidth(in: width) }

    func index(at x: CGFloat, width: CGFloat) -> Int? {
        guard !tabs.isEmpty, x >= TabStrip.lead, x < width - TabStrip.trail, tabWidth(in: width) > 0 else { return nil }
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
            HStack(spacing: 0) {
                TabStripCorner(tint: leadTint)
                Spacer(minLength: 0)
                TabStripCorner(tint: 0).scaleEffect(x: -1)
            }
            .frame(height: TabStrip.corner)
            .animation(fade(TabStrip.reduceMotion ? Motion.fade : Motion.easeOut), value: model.active)
            .animation(fade(Motion.fade), value: model.focused)
            .animation(fade(Motion.fade), value: model.hovered)
        }
    }

    private var leadTint: Double {
        guard let first = model.tabs.first?.id else { return 0 }
        if first == model.active { return model.focused ? 0.1 : 0.06 }
        return model.hovered == first && model.dragged == nil ? 0.04 : 0
    }

    private var bar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let tabWidth = model.tabWidth(in: width)
            ZStack(alignment: .topLeading) {
                if let hovered = model.hovered, hovered != model.active, model.dragged == nil,
                   let index = model.tabs.firstIndex(where: { $0.id == hovered }) {
                    fill(index).fill(Theme.ink.opacity(0.04))
                        .frame(width: tabWidth, height: TabStrip.height)
                        .offset(x: model.slotX(index, width: width))
                }
                if let index = model.tabs.firstIndex(where: { $0.id == model.active }) {
                    fill(index).fill(Theme.ink.opacity(model.focused ? 0.1 : 0.06))
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
        .background { TabStripBackdrop() }
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

    private func fill(_ index: Int) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: index == 0 ? TabStrip.radius : 0, style: .continuous)
    }

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
    var body: some View {
        ZStack {
            Theme.surface
            Theme.ink.opacity(0.04)
        }
    }
}

private struct TabStripCorner: View {
    let tint: Double

    private var arc: Path {
        let side = TabStrip.corner
        var path = Path()
        path.addRelativeArc(center: CGPoint(x: side, y: side), radius: side,
                            startAngle: .degrees(270), delta: .degrees(-90))
        return path
    }

    private var edge: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.5, y: TabStrip.corner))
        return path
    }

    private var wedge: Path {
        var path = arc
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }

    var body: some View {
        ZStack {
            TabStripBackdrop().clipShape(wedge)
            Theme.ink.opacity(tint).clipShape(wedge)
            edge.stroke(Theme.hairline, lineWidth: 1)
        }
        .frame(width: TabStrip.corner, height: TabStrip.corner)
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
                if hovered {
                    Image(systemName: "xmark")
                        .font(Theme.symbol(Theme.Icon.extraSmall, .bold))
                        .frame(width: TabStrip.closeSide, height: TabStrip.closeSide)
                        .background(Circle().fill(closeHovered ? Theme.well : .clear))
                        .accessibilityLabel("Close tab")
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Space.small)
        }
        .foregroundStyle(active && focused || hovered ? Theme.ink : Theme.inkMuted)
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

#if DEBUG
extension GalleryExamples {
    static let tabStrip = GalleryExample(order: 19) { AnyView(GalleryContent(model: $0).tabStrip) }
}

extension GalleryContent {
    @ViewBuilder var tabStrip: some View {
        block("Tab strip") {
            VStack(alignment: .leading, spacing: Theme.Space.large) {
                ForEach([true, false], id: \.self) { focused in
                    ZStack(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.pane,
                                               topTrailingRadius: Theme.Radius.pane, style: .continuous)
                            .fill(Theme.surfaceRaised)
                            .frame(width: 520, height: Theme.controlHeight)
                            .padding(.top, TabStrip.height)
                        TabStripView(model: .example(focused: focused))
                            .frame(width: 520, height: TabStrip.panelHeight)
                    }
                    .frame(width: 520, height: TabStrip.height + Theme.controlHeight, alignment: .top)
                }
            }
        }
    }
}

private extension TabStripModel {
    static func example(focused: Bool) -> TabStripModel {
        let model = TabStripModel()
        let pid = ProcessInfo.processInfo.processIdentifier
        model.tabs = ["Notes", "Terminal", "Design review"].enumerated().map { index, title in
            Tab(id: CGWindowID(index + 1), title: title, pid: pid)
        }
        model.active = 1
        model.focused = focused
        model.hovered = focused ? 3 : nil
        return model
    }
}
#endif
