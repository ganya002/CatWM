import AppKit
import CatWMKit
import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 360
    static let visibleRows = 10
    static var margin: CGFloat { Elevation.popover.room }
    private static let inset = Theme.Space.extraSmall + Theme.Space.xxs
    private static let headHeight: CGFloat = 34

    static func size(rows: Int) -> CGSize {
        CGSize(width: width + margin * 2, height: headHeight + 1 + listHeight(rows: rows) + inset * 3 + margin * 2)
    }

    private static func listHeight(rows: Int) -> CGFloat {
        CGFloat(min(max(rows, 1), visibleRows)) * Theme.rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.bottom, Self.inset)
            list
        }
        .frame(width: Self.width - Self.inset * 2)
        .surface(.medium)
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown || reduceMotion ? 1 : 0.97)
        .animation(model.shown ? Motion.fade : Motion.exit, value: model.shown)
        .padding(Self.margin)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window switcher")
    }

    private var head: some View {
        HStack(spacing: Theme.Space.small) {
            Image(systemName: "magnifyingglass").font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
            Text(model.query.isEmpty ? placeholder : model.query)
                .font(Theme.body(13.5))
                .foregroundStyle(model.query.isEmpty ? Theme.inkFaint : Theme.ink)
                .oneLine()
            Spacer(minLength: Theme.Space.small)
            if let app = model.appFilter {
                Text(app.app).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.horizontal, Theme.Space.medium)
        .frame(height: Self.headHeight)
        .accessibilityElement(children: .combine)
    }

    private var placeholder: String {
        model.appFilter.map { "Search \($0.app) windows" } ?? "Type to search windows"
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.results.isEmpty {
                        Text("No windows match").font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: Theme.rowHeight)
                    }
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index).id(item.id)
                    }
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ListOffset.self,
                                           value: -geometry.frame(in: .named(Self.listSpace)).minY)
                })
            }
            .coordinateSpace(name: Self.listSpace)
            .onPreferenceChange(ListOffset.self) { offset in
                if abs(model.scrolled - offset) > 0.5 { model.scrolled = offset }
            }
            .scrollIndicators(.never)
            .frame(height: listHeight)
            .mask(overflowMask)
            .animation(Motion.fade, value: hiddenAbove)
            .animation(Motion.fade, value: hiddenBelow)
            .onChange(of: model.selection) { _, _ in
                if let id = model.selected?.id { proxy.scrollTo(id) }
            }
        }
    }

    private static let listSpace = "switcherList"
    private var listHeight: CGFloat { Self.listHeight(rows: model.results.count) }
    private var hiddenAbove: Bool { model.scrolled > 1 }
    private var hiddenBelow: Bool { CGFloat(model.results.count) * Theme.rowHeight - model.scrolled > listHeight + 1 }

    private var overflowMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(hiddenAbove ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.rowHeight)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(hiddenBelow ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.rowHeight)
        }
    }

    private func row(_ item: SwitcherItem, index: Int) -> some View {
        OMenuRow(highlight: .fixed(index == model.selection), action: { model.onPick?(item) }, lead: {
            AppIcon(pid: item.pid)
        }, label: {
            HStack(spacing: Theme.Space.small) {
                Text(item.title.isEmpty ? item.app : item.title).oneLine().layoutPriority(1)
                if !item.title.isEmpty {
                    Text(item.app).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
            }
        }, trailing: {
            if !item.workspace.isEmpty {
                Text(item.workspace).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
            }
        })
        .accessibilityLabel(item.title.isEmpty ? item.app : "\(item.title), \(item.app)")
        .accessibilityValue(item.workspace.isEmpty ? "" : "Workspace \(item.workspace)")
        .accessibilityAddTraits(index == model.selection ? .isSelected : [])
    }
}

private struct AppIcon: View {
    let pid: pid_t
    @ObservedObject private var icons = AppIcons.shared

    var body: some View {
        if let icon = icons.icon(for: pid) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "macwindow").font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
        }
    }
}

private struct ListOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
