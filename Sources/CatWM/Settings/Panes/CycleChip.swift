import AppKit
import CatWMKit
import SwiftUI

struct CycleChip: View {
    static let width: CGFloat = 78
    static let gap: CGFloat = 12
    static let space = "cycleRow"
    let index: Int
    let layout: Layout
    let count: Int
    @ObservedObject var drag: CycleDrag
    let keys: (left: Set<String>, right: Set<String>)
    let move: (Int) -> Void
    let remove: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        let dragging = drag.layout == layout
        VStack(spacing: 6) {
            LayoutThumbnail(layout: layout, selected: true).frame(width: 72)
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)").font(Theme.body(11, .medium)).foregroundStyle(Theme.background)
                        .contentTransition(.numericText())
                        .frame(width: 18, height: 18).background(Circle().fill(Theme.ink))
                        .offset(x: -6, y: -6)
                }
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        RemoveButton(help: "Remove \(layout.title)", variant: .badge, action: remove)
                            .offset(x: 6, y: -6)
                            .opacity(hover.isOn && !dragging ? 1 : 0)
                            .scaleEffect(hover.isOn && !dragging ? 1 : 0.5)
                    }
                }
            Text(layout.shortTitle).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                .frame(width: Self.width)
        }
        .frame(width: Self.width)
        .scaleEffect(dragging ? 1.06 : 1)
        .offset(x: dragging ? drag.x : 0)
        .zIndex(dragging ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: hover.isOn)
        .animation(Motion.fade, value: dragging)
        .onTapGesture { remove() }
        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag.layout != layout { drag.layout = layout; drag.origin = index }
                let steps = Int((value.translation.width / (Self.width + Self.gap)).rounded())
                let target = min(max(drag.origin + steps, 0), count - 1)
                drag.x = value.translation.width - CGFloat(target - drag.origin) * (Self.width + Self.gap)
                if target != index { move(target) }
            }
            .onEnded { _ in
                withAnimation(Motion.snap) { drag.x = 0; drag.layout = nil }
            })
        .focusable()
        .onKeyPress(phases: .down) { press in
            let typed = press.characters.lowercased()
            if press.key == .leftArrow || keys.left.contains(typed) { move(index - 1); return .handled }
            if press.key == .rightArrow || keys.right.contains(typed) { move(index + 1); return .handled }
            if press.key == .delete || press.key == .deleteForward { remove(); return .handled }
            return .ignored
        }
        .accessibilityLabel("\(layout.title), \(index + 1) of \(count)")
        .accessibilityHint("Drag or use the arrow keys to move, click to remove")
    }
}

final class CycleDrag: ObservableObject {
    @Published var layout: Layout?
    @Published var x: CGFloat = 0
    var origin = 0
}
