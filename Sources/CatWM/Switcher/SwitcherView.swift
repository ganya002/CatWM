import AppKit
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace var morph

    enum Mode { case bar, search, peek }

    struct Tile {
        let width: CGFloat, height: CGFloat, iconSize: CGFloat
        static let icon = Tile(width: 104, height: 104, iconSize: 72)
        static let preview = Tile(width: 264, height: 180, iconSize: 32)
        static let inner = Theme.Space.small
    }

    func tileWidth(_ item: SwitcherItem) -> CGFloat {
        guard model.previewing else { return tile.width }
        let size = model.previews[item.id]?.size ?? item.size
        let aspect = size.width > 0 && size.height > 0 ? size.width / size.height : tile.width / tile.height
        let height = tile.height - Tile.inner * 2
        return (height * min(max(aspect, 0.5), 2.4)).rounded() + Tile.inner * 2
    }

    static let searchWidth: CGFloat = 360
    static let visibleRows = 10
    static let headHeight: CGFloat = 34
    static let inset = Theme.Space.extraSmall + Theme.Space.xxs
    static var margin: CGFloat { Elevation.popover.room }

    static func room(_ width: CGFloat) -> CGFloat { width - (inset + margin) * 2 }

    static func peekSize(_ room: CGFloat) -> CGSize {
        let width = min(room * 0.7, 1280)
        return CGSize(width: width, height: (width * 0.6).rounded())
    }

    static func size(width: CGFloat) -> CGSize {
        let search = headHeight + 1 + inset + CGFloat(visibleRows) * Theme.rowHeight
        let peek = peekSize(room(width)).height + Theme.Space.extraSmall + Theme.rowHeight
        let bar = Tile.preview.height + Theme.Space.extraSmall + Theme.rowHeight
        return CGSize(width: width, height: max(search, peek, bar) + (inset + margin) * 2)
    }

    var mode: Mode { model.searching ? .search : model.peeking ? .peek : .bar }
    var tile: Tile { model.previewing ? .preview : .icon }

    var body: some View {
        GeometryReader { space in
            ZStack(alignment: .top) {
                Color.clear.contentShape(Rectangle()).onTapGesture { model.onDismiss?() }
                card(room: Self.room(space.size.width))
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

    private func card(room: CGFloat) -> some View {
        VStack(spacing: 0) {
            switch mode {
            case .bar: bar
            case .search: search
            case .peek: peek(Self.peekSize(room))
            }
        }
        .transition(.opacity)
        .frame(width: width(room: room))
        .surface(.medium)
        .animation(change, value: mode)
    }

    private func width(room: CGFloat) -> CGFloat? {
        switch mode {
        case .bar:
            model.results.isEmpty ? nil : min(model.results.map(tileWidth).reduce(0, +), room)
        case .search: Self.searchWidth - Self.inset * 2
        case .peek: Self.peekSize(room).width
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
