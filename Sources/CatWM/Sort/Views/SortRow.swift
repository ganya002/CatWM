import AppKit
import CatWMKit
import SwiftUI

struct SortRow: View {
    enum Tab {
        case middle
        case last
    }

    @ObservedObject var model: SortModel
    let item: SortItem
    let closing: Bool
    var indented = false
    var tab: Tab?
    @StateObject private var menu = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pointed = model.hover == item.id
        let lit = pointed || model.selected == item.id || menu.isOn
        let lead: CGFloat = tab != nil ? SortMetrics.tabIndent : indented ? 5 + SortMetrics.closedIndent : 5
        SortRowFace(item: item, closing: closing)
            .padding(.leading, lead).padding(.trailing, 8)
            .frame(height: SortMetrics.rowHeight)
            .background(alignment: .leading) { if let tab { SortTabBracket(last: tab == .last) } }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill((closing ? pointed || menu.isOn : lit) ? Theme.hover : .clear))
            .overlay(alignment: .trailing) {
                if pointed && model.drag == nil {
                    RemoveButton(help: closing ? "Bring back" : "Close window", variant: closing ? .restore : .close,
                                 tooltip: false) {
                        if closing { model.restore(item.id) } else { model.markClosing(item.id) }
                    }
                    .padding(.trailing, 2)
                    .transition(.opacity)
                }
            }
            .opacity(model.drag?.carries(item.id) == true ? 0.3 : 1)
            .contentShape(Rectangle())
            .zone(.row(item.id))
            .onHover { inside in
                if inside {
                    model.hover = item.id
                } else if model.hover == item.id, model.drag == nil {
                    model.hover = nil
                }
            }
            .onTapGesture { if closing { model.restore(item.id) } else { model.selected = item.id } }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
                .onChanged { model.dragChanged(item, $0) }
                .onEnded { _ in model.dragEnded() })
            .oContextMenu(opened: { menu.isOn = $0 }, items: {
                model.windowMenu(item, closing: closing, tabbed: tab != nil) { change in
                    withAnimation(Motion.user(reduceMotion: reduceMotion), change)
                }
            })
            .accessibilityLabel("\(item.title), \(item.app)")
    }
}

struct SortTabBracket: View {
    let last: Bool

    var body: some View {
        Path { path in
            let x: CGFloat = 15
            let mid = SortMetrics.rowHeight / 2
            let bend = Theme.Radius.small
            let end = SortMetrics.tabIndent - Theme.Space.extraSmall
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: mid - bend))
            path.addQuadCurve(to: CGPoint(x: x + bend, y: mid), control: CGPoint(x: x, y: mid))
            path.addLine(to: CGPoint(x: end, y: mid))
            if !last {
                path.move(to: CGPoint(x: x, y: mid - bend))
                path.addLine(to: CGPoint(x: x, y: SortMetrics.rowHeight))
            }
        }
        .stroke(Theme.borderControl.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .frame(width: SortMetrics.tabIndent, height: SortMetrics.rowHeight)
    }
}

struct SortRowFace: View {
    let item: SortItem
    let closing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous).fill(Theme.tint)
                        .overlay(Text(String(item.app.prefix(1)))
                            .font(Theme.body(10.5, .medium)).foregroundStyle(Theme.ink))
                }
            }
            .frame(width: 20, height: 20)
            (Text(item.title).foregroundColor(closing ? Theme.inkMuted : Theme.ink)
                + Text(item.title.localizedCaseInsensitiveContains(item.app) ? "" : "  " + item.app)
                    .textStyle(.caption).foregroundColor(Theme.inkFaint))
                .strikethrough(closing, color: Theme.danger)
                .oneLine()
            Spacer(minLength: 0)
        }
        .font(Theme.body(13.5))
    }
}
