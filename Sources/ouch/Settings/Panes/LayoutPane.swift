import AppKit
import SwiftUI

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
