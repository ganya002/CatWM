import AppKit
import CatWMKit
import SwiftUI

struct MenuRoot: View {
    @ObservedObject var model: MenuModel
    let rootX: CGFloat
    let top: CGFloat
    let size: CGSize
    var rootWidth: CGFloat = Theme.menuWidth
    var fromBottom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { model.close() }
            column(0, width: rootWidth)
                .padding(.leading, rootX).padding(.top, fromBottom ? 0 : top).padding(.bottom, fromBottom ? top : 0)
                .frame(height: fromBottom ? size.height : nil, alignment: .bottom)
                .transaction { $0.animation = nil }
                .scaleEffect(model.appeared || reduceMotion ? 1 : 0.97, anchor: fromBottom ? .bottom : .top)
                .opacity(model.appeared ? 1 : 0)
            ForEach(Array(model.path.enumerated()), id: \.element) { i, id in
                if let parent = model.item(id), let row = model.rowFrames[id] {
                    let level = i + 1
                    let height = model.columnHeights[level] ?? 0
                    let y = max(top, min(row.minY - 4, size.height - height - top))
                    let x = model.opensLeft ? row.minX - 4 - parent.width - 2 : row.maxX + 4 + 2
                    column(level, width: parent.width)
                        .padding(.leading, x).padding(.top, y)
                        .transition(.opacity.combined(with: .offset(x: model.opensLeft ? 4 : -4)))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "menu")
        .onPreferenceChange(RowFrameKey.self) { frames in if frames != model.rowFrames { model.rowFrames = frames } }
        .onPreferenceChange(ColumnHeightKey.self) { heights in
            if heights != model.columnHeights { model.columnHeights = heights }
        }
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private func column(_ level: Int, width: CGFloat) -> some View {
        MenuColumn(model: model, level: level)
            .frame(width: width)
            .surface(.medium)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ColumnHeightKey.self, value: [level: geo.size.height])
            })
            .onHover { if $0 { model.enterColumn(level) } }
    }
}

struct RowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ColumnHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}
