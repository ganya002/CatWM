import AppKit
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var morph

    enum Mode { case bar, search, peek }

    enum Tile {
        static let inner = Theme.Space.small
        static let barShare: CGFloat = 1 / 3
        static let iconShare: CGFloat = 1 / 2
        static let badgeShare: CGFloat = 1 / 5
    }

    static let searchWidth: CGFloat = 360
    static let headHeight = Theme.rowHeight + Theme.Space.extraSmall
    static let inset = Theme.Space.extraSmall + Theme.Space.xxs
    static var margin: CGFloat { Elevation.popover.room }

    static func room(_ size: CGSize) -> CGSize {
        CGSize(width: size.width - (inset + margin) * 2, height: size.height - (inset + margin) * 2)
    }

    static func windowSize(_ item: SwitcherItem, room: CGSize) -> CGSize {
        item.size.width > 0 && item.size.height > 0 ? item.size : room
    }

    static func fit(_ size: CGSize, in room: CGSize) -> CGSize {
        let scale = min(1, room.width / size.width, room.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    static func barScale(_ items: [SwitcherItem], room: CGSize) -> CGFloat {
        let sizes = items.map { windowSize($0, room: room) }
        let wide = (room.width - CGFloat(sizes.count) * Tile.inner * 2) / max(sizes.map(\.width).reduce(0, +), 1)
        let tall = (room.height - Theme.rowHeight) * Tile.barShare / max(sizes.map(\.height).max() ?? 1, 1)
        return min(wide, tall, 1)
    }

    static func tileSize(_ item: SwitcherItem, scale: CGFloat, room: CGSize) -> CGSize {
        let size = windowSize(item, room: room)
        return CGSize(width: (size.width * scale).rounded() + Tile.inner * 2,
                      height: (size.height * scale).rounded() + Tile.inner * 2)
    }

    var mode: Mode { model.searching ? .search : model.peeking ? .peek : .bar }

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .top) {
                Color.clear.contentShape(Rectangle()).onTapGesture { model.onDismiss?() }
                card(room: Self.room(space.size))
                    .opacity(model.shown ? 1 : 0)
                    .scaleEffect(model.shown || reduceMotion ? 1 : 0.97, anchor: .top)
                    .animation(animated ? model.shown ? Motion.fade : Motion.exit : nil, value: model.shown)
            }
            .padding(Self.margin)
            .frame(width: space.size.width, height: space.size.height, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window switcher")
    }

    var animated: Bool { WindowManager.shared.config.animate }
    var change: Animation? { PanelMotion.windowAnimation(reduceMotion: reduceMotion) }
    var fade: Animation? { animated ? Motion.fade : nil }

    private func card(room: CGSize) -> some View {
        let scale = Self.barScale(model.results, room: room)
        let peek = model.selected.map { Self.fit(Self.windowSize($0, room: room), in: room) } ?? .zero
        return VStack(spacing: 0) {
            switch mode {
            case .bar: bar(scale: scale, room: room)
            case .search: search(room: room)
            case .peek: self.peek(peek)
            }
        }
        .transition(.opacity)
        .frame(width: width(scale: scale, peek: peek, room: room))
        .surface(.medium)
        .animation(change, value: mode)
    }

    private func width(scale: CGFloat, peek: CGSize, room: CGSize) -> CGFloat? {
        switch mode {
        case .bar:
            model.results.isEmpty ? nil
                : model.results.map { Self.tileSize($0, scale: scale, room: room).width }.reduce(0, +)
        case .search: Self.searchWidth - Self.inset * 2
        case .peek: peek.width
        }
    }

    func label(_ item: SwitcherItem) -> String {
        item.title.isEmpty ? item.app : "\(item.title), \(item.app)"
    }

    @ViewBuilder func appIcon(_ pid: pid_t, size: CGFloat) -> some View {
        if let icon = model.icon(pid) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "macwindow").font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
                .frame(width: size, height: size)
        }
    }

    func titleLine(_ item: SwitcherItem) -> some View {
        HStack(spacing: Theme.Space.small) {
            Text(item.app).font(Theme.body(13.5, .bold)).oneLine().fixedSize()
            if !item.title.isEmpty {
                Text(item.title).font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.horizontal, OMenuRowStyle.inset)
        .frame(height: Theme.rowHeight)
    }
}
