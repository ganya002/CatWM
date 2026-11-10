import AppKit
import CatWMKit
import SwiftUI

struct SortLayoutPill: View {
    let layout: Layout
    let next: () -> Void
    let previous: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: next) {
            HStack(spacing: 6) {
                SortLayoutGlyph(layout: layout).frame(width: 16, height: 14)
                Text(layout == .bsp ? "BSP" : layout.title).textStyle(.caption).oneLine()
            }
            .foregroundStyle(hover.isOn ? Theme.ink : Theme.inkMuted)
            .padding(.leading, Theme.Space.small).padding(.trailing, Theme.Space.medium)
            .frame(height: Theme.controlHeight)
            .background(Capsule().fill(hover.isOn ? Theme.well : .clear))
            .overlay(Capsule().strokeBorder(Theme.borderControl, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(SortRightClick(action: previous))
        .onHover { hover.isOn = $0 }
        .animation(Motion.fade, value: hover.isOn)
        .accessibilityLabel("Layout: \(layout.title)")
        .accessibilityAction(named: "Previous layout", previous)
    }
}

struct SortLayoutGlyph: View {
    let layout: Layout

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 1, dy: 0.5)
            let frames = layout.frames(count: paneCount, in: bounds.insetBy(dx: -0.75, dy: -0.75),
                                       ratio: 0.5, mainCount: 1)?
                .map { $0.insetBy(dx: 0.75, dy: 0.75) }
                ?? [CGRect(x: 1, y: 1, width: 9, height: 8), CGRect(x: 5, y: 4, width: 10, height: 9)]
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 1.4, style: .continuous) // style-ok: a glyph-size drawing
                        .frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .opacity(0.8)
        .accessibilityHidden(true)
    }

    private var paneCount: Int {
        switch layout {
        case .fullscreen: 1
        case .bsp: 4
        case .twoPane, .twoPaneRight: 2
        default: 3
        }
    }
}
