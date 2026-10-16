// Settings: the Layout pane (layout cycle chips, layout grid, gaps preview).
import AppKit
import SwiftUI

// MARK: - Layout

struct LayoutPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var drag = CycleDrag()

    private var allPadding: Binding<CGFloat> {
        Binding(get: { doc.config.paddingTop }, set: { v in
            doc.config.paddingTop = v; doc.config.paddingBottom = v; doc.config.paddingLeft = v; doc.config.paddingRight = v
        })
    }

    var body: some View {
        let c = doc.config
        let s = ui.status
        VStack(alignment: .leading, spacing: 30) {
            if s.trusted && !s.screens.isEmpty {
                OGroup("Displays") {
                    ForEach(s.screens, id: \.uuid) { screen in
                        HStack(spacing: 14) {
                            ScreenThumbnail(layout: screen.layout).frame(width: 56)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(screen.name).font(Theme.body(14)).oneLine()
                                Text(screen.workspace.isEmpty ? "Current layout" : "Workspace \(screen.workspace)")
                                    .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                            }
                            Spacer(minLength: 8)
                            OMenuPicker(title: "Layout for \(screen.name)", options: Layout.allCases.map { ($0, $0.title) },
                                        selection: Binding(get: { screen.layout }, set: { l in
                                            WindowManager.shared.setLayout(l, screen: screen.uuid)
                                            ui.refreshStatus()
                                        }))
                        }
                        .frame(minHeight: 48).padding(.vertical, 8)
                    }
                }
                .setting("layout.displays", ui)
            }

            OGroup("Active layouts", footer: "Next Layout goes through these in order. Drag to change the order, or click one to remove it. Click a layout below to add it.") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CycleChip.gap) {
                        ForEach(c.layouts, id: \.self) { l in
                            let i = c.layouts.firstIndex(of: l) ?? 0
                            CycleChip(index: i, layout: l, count: c.layouts.count, drag: drag, keys: moveKeys,
                                      move: { to in
                                          let to = min(max(to, 0), doc.config.layouts.count - 1)
                                          guard let from = doc.config.layouts.firstIndex(of: l), from != to else { return }
                                          withAnimation(Motion.snap(reduceMotion)) {
                                              doc.config.layouts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                          }
                                      },
                                      remove: {
                                          guard doc.config.layouts.count > 1 else { return }
                                          withAnimation(Motion.snap(reduceMotion)) { doc.config.layouts.removeAll { $0 == l } }
                                      })
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                    .coordinateSpace(name: CycleChip.space)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Layout.allCases, id: \.self) { cell($0) }
                }
                .padding(.vertical, 10)
            }
            .setting("layout.cycle", ui)

            OGroup("Gaps") {
                GapsPreview(config: c, layout: c.layouts.first { ![.floating, .fullscreen].contains($0) } ?? .tall)
                    .frame(height: 170)
                    .padding(.vertical, 12)
                OptionSwitch(\.windowMargins, doc: doc, ui: ui)
                OptionSlider(\.windowMarginSize, doc: doc, ui: ui, width: 180, format: { "\(Int($0)) pt" })
                    .disabled(!c.windowMargins)
                OptionSwitch(\.smartWindowMargins, doc: doc, ui: ui)
                    .disabled(!c.windowMargins)
                if ui.linkedPadding {
                    ORow("Screen padding", description: "Space between windows and the screen edges") { points(allPadding, "Screen padding") }
                        .setting("layout.padding", ui)
                } else {
                    ORow("Top padding") { points($doc.config.paddingTop, "Top padding") }.setting("layout.padding", ui)
                    ORow("Bottom padding") { points($doc.config.paddingBottom, "Bottom padding") }
                    ORow("Left padding") { points($doc.config.paddingLeft, "Left padding") }
                    ORow("Right padding") { points($doc.config.paddingRight, "Right padding") }
                }
                OptionSwitch(\.disablePaddingOnBuiltinDisplay, doc: doc, ui: ui)
            }

            OGroup("Main pane") {
                OptionSlider(\.windowResizeStep, doc: doc, ui: ui, format: { "\(Int($0))%" })
            }

            OGroup("Feedback") {
                OptionSwitch(\.enablesLayoutHUD, doc: doc, ui: ui)
            }

            AdvancedSection(pane: .layout, ui: ui) {
                OGroup("Gaps and padding") {
                    OSwitchRow("Same padding on every side", isOn: Binding(get: { ui.linkedPadding }, set: { on in
                        withAnimation(Motion.easeOut) { ui.linkedPadding = on }
                        if on { allPadding.wrappedValue = c.paddingTop }
                    }))
                    .setting("layout.linked", ui)
                    OptionSwitch(\.ignoreMenuBar, doc: doc, ui: ui)
                }
                OGroup("Feedback") {
                    OptionSwitch(\.enablesLayoutHUDOnSpaceChange, doc: doc, ui: ui)
                        .disabled(!c.enablesLayoutHUD)
                }
            }
        }
    }

    /// The keys bound to focus left and right, so a focused layout moves with them as well as the arrows.
    private var moveKeys: (left: Set<String>, right: Set<String>) {
        var left = Set<String>(), right = Set<String>()
        for submap in doc.submaps {
            for a in doc.keyActions(in: submap) where a.row.dispatcher == "movefocus" && a.key.count == 1 {
                if a.arg == "l" { left.insert(a.key.lowercased()) } else if a.arg == "r" { right.insert(a.key.lowercased()) }
            }
        }
        return (left, right)
    }

    private func points(_ value: Binding<CGFloat>, _ label: String) -> some View {
        OSlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0.rounded()) }),
                range: 0...60, step: 1, ticks: [10], resetValue: 10, width: 180, label: label, format: { "\(Int($0)) pt" })
    }

    private func cell(_ l: Layout) -> some View {
        let index = doc.config.layouts.firstIndex(of: l)
        let on = index != nil
        let locked = on && doc.config.layouts.count == 1
        return LayoutCell(layout: l, on: on) {
            withAnimation(Motion.snap(reduceMotion)) {
                if let index { if !locked { doc.config.layouts.remove(at: index) } } else { doc.config.layouts.append(l) }
            }
        }
    }
}

// MARK: - Cycle chips and layout grid

final class CycleDrag: ObservableObject {
    @Published var layout: Layout?
    @Published var x: CGFloat = 0
    var origin = 0
}

/// An active layout, numbered. Drag it to reorder, click it to remove it, or Tab to it and use the
/// arrow keys (or the keys you bound to focus left and right).
private struct CycleChip: View {
    static let width: CGFloat = 78
    static let gap: CGFloat = 12
    /// The row's own space: a chip's local space moves as it is reordered, which made the drag jitter.
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
                    Text("\(index + 1)").font(Theme.body(11, .medium)).foregroundStyle(Theme.onAccent)
                        .contentTransition(.numericText())
                        .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                        .offset(x: -6, y: -6)
                }
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        RemoveButton(help: "Remove \(layout.title)", variant: .badge, action: remove)
                            .offset(x: 6, y: -6)
                            .opacity(hover.on && !dragging ? 1 : 0)
                            .scaleEffect(hover.on && !dragging ? 1 : 0.5)
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
        .onHover { hover.on = $0 }
        .animation(Motion.fade, value: hover.on)
        .animation(Motion.fade, value: dragging)
        .onTapGesture { remove() }
        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.space))
            .onChanged { v in
                if drag.layout != layout { drag.layout = layout; drag.origin = index }
                let target = min(max(drag.origin + Int((v.translation.width / (Self.width + Self.gap)).rounded()), 0), count - 1)
                drag.x = v.translation.width - CGFloat(target - drag.origin) * (Self.width + Self.gap)
                if target != index { move(target) }
            }
            .onEnded { _ in
                // Settle into the slot while it stops being lifted, instead of snapping.
                withAnimation(Motion.snap) { drag.x = 0; drag.layout = nil }
            })
        .focusable()
        .onKeyPress(phases: .down) { press in
            let c = press.characters.lowercased()
            if press.key == .leftArrow || keys.left.contains(c) { move(index - 1); return .handled }
            if press.key == .rightArrow || keys.right.contains(c) { move(index + 1); return .handled }
            if press.key == .delete || press.key == .deleteForward { remove(); return .handled }
            return .ignored
        }
        .accessibilityLabel("\(layout.title), \(index + 1) of \(count)")
        .accessibilityHint("Drag or use the arrow keys to move, click to remove")
    }
}

/// A display with its layout on it.
private struct ScreenThumbnail: View {
    let layout: Layout

    var body: some View {
        VStack(spacing: 2) {
            LayoutThumbnail(layout: layout, selected: true)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous).strokeBorder(Theme.borderControl, lineWidth: 1.5))
            Capsule().fill(Theme.borderControl).frame(width: 14, height: 2.5)
        }
    }
}

/// A layout in the grid; in the cycle it's lit and lands with a bump.
private struct LayoutCell: View {
    let layout: Layout
    let on: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            LayoutThumbnail(layout: layout, selected: on)
                .squish(on: on, when: on)
                .scaleEffect(hover.on ? 1.06 : 1)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(on ? Theme.accentSoft : hover.on ? Theme.wellHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(Motion.spring, value: hover.on)
        .accessibilityLabel("\(layout.title), \(on ? "in the cycle" : "not in the cycle")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Gaps preview

/// The main display, scaled down, with three windows placed exactly as the tiler would place them. They
/// spring to their new places as gaps and padding change.
struct GapsPreview: View {
    let config: Config
    let layout: Layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Desktop backdrop shared with the animation preview: a quiet wash of the palette.
    static let wallpaper = LinearGradient(colors: [Theme.accentSoft, Theme.tint], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let full = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let menuBar = (screen.map { $0.frame.maxY - $0.visibleFrame.maxY }) ?? 24
        let dock = (screen.map { $0.visibleFrame.minY - $0.frame.minY }) ?? 0
        GeometryReader { g in
            let scale = min(g.size.width / full.width, g.size.height / full.height)
            let w = full.width * scale, h = full.height * scale
            let bar = config.ignoreMenuBar ? 0 : menuBar * scale
            let frames = windows(in: CGRect(x: 0, y: bar, width: w, height: h - bar - dock * scale), scale: scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Self.wallpaper)
                Rectangle().fill(Theme.ink.opacity(0.1)).frame(width: w, height: menuBar * scale)
                    .opacity(config.ignoreMenuBar ? 0 : 1)
                ForEach(Array(frames.enumerated()), id: \.offset) { i, f in
                    RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                        .fill(i == 0 ? Theme.accent : Theme.thumbMain)
                        .frame(width: max(f.width, 0), height: max(f.height, 0))
                        .position(x: f.midX, y: f.midY)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .frame(width: g.size.width, height: g.size.height)
            // Dragging a slider retargets constantly, which a spring takes in stride.
            .animation(Motion.snap(reduceMotion), value: geometry)
        }
        .accessibilityHidden(true)
    }

    /// Everything from the settings that moves the windows.
    private var geometry: [CGFloat] {
        [config.paddingTop, config.paddingBottom, config.paddingLeft, config.paddingRight, config.windowMarginSize,
         config.windowMargins ? 1 : 0, config.ignoreMenuBar ? 1 : 0]
    }

    private func windows(in area: CGRect, scale: CGFloat) -> [CGRect] {
        let usable = CGRect(x: area.minX + config.paddingLeft * scale, y: area.minY + config.paddingTop * scale,
                            width: area.width - (config.paddingLeft + config.paddingRight) * scale,
                            height: area.height - (config.paddingTop + config.paddingBottom) * scale)
        let gap = (config.windowMargins ? config.windowMarginSize : 0) * scale
        guard usable.width > 4, usable.height > 4,
              let frames = layout.frames(count: 3, in: usable.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)
        else { return [] }
        return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
    }
}
