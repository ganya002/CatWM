import AppKit
import CatWMKit
import SwiftUI

struct LayoutPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var drag = CycleDrag()

    private var allPadding: Binding<CGFloat> {
        Binding(get: { doc.config.paddingTop }, set: { value in
            doc.config.paddingTop = value; doc.config.paddingBottom = value
            doc.config.paddingLeft = value; doc.config.paddingRight = value
        })
    }

    var body: some View {
        let config = doc.config
        let status = settingsUI.status
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            if status.trusted && !status.screens.isEmpty {
                OGroup("Displays") {
                    ForEach(status.screens, id: \.uuid) { screen in
                        HStack(spacing: Theme.Space.medium) {
                            ScreenThumbnail(layout: screen.layout).frame(width: 56)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(screen.name).font(Theme.body()).oneLine()
                                Text(screen.workspace.isEmpty ? "Current layout" : "Workspace \(screen.workspace)")
                                    .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                            }
                            Spacer(minLength: 8)
                            OMenuPicker(title: "Layout for \(screen.name)",
                                        options: Layout.allCases.map { ($0, $0.title) },
                                        selection: Binding(get: { screen.layout }, set: { layout in
                                            WindowManager.shared.setLayout(layout, screen: screen.uuid)
                                            settingsUI.refreshStatus()
                                        }))
                        }
                        .frame(minHeight: 48).padding(.vertical, 8)
                    }
                }
                .setting(LayoutPane.searchDisplays.id, settingsUI)
            }

            OGroup(LayoutPane.searchCycle.title,
                   footer: "Next Layout goes through these in order. Drag to change the order, "
                       + "or click one to remove it. Click a layout below to add it.") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CycleChip.gap) {
                        ForEach(config.layouts, id: \.self) { layout in
                            let i = config.layouts.firstIndex(of: layout) ?? 0
                            CycleChip(index: i, layout: layout, count: config.layouts.count, drag: drag, keys: moveKeys,
                                      move: { target in move(layout, to: target) },
                                      remove: { remove(layout) })
                        }
                    }
                    .padding(.vertical, Theme.Space.small).padding(.horizontal, 8)
                    .coordinateSpace(name: CycleChip.space)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Layout.allCases, id: \.self) { cell($0) }
                }
                .padding(.vertical, Theme.Space.small)
            }
            .setting(LayoutPane.searchCycle.id, settingsUI)

            OGroup("Gaps") {
                GapsPreview(config: config,
                            layout: config.layouts.first { ![.floating, .fullscreen].contains($0) } ?? .tall)
                    .frame(height: 170)
                    .padding(.vertical, 12)
                OptionRows(pane: .layout, section: "Gaps", doc: doc, settingsUI: settingsUI)
                if settingsUI.linkedPadding {
                    ORow(LayoutPane.searchPadding.title, description: "Space between windows and the screen edges") {
                        points(allPadding, "Screen padding")
                    }
                        .setting(LayoutPane.searchPadding.id, settingsUI)
                } else {
                    ORow("Top padding") { points($doc.config.paddingTop, "Top padding") }
                        .setting(LayoutPane.searchPadding.id, settingsUI)
                    ORow("Bottom padding") { points($doc.config.paddingBottom, "Bottom padding") }
                    ORow("Left padding") { points($doc.config.paddingLeft, "Left padding") }
                    ORow("Right padding") { points($doc.config.paddingRight, "Right padding") }
                }
                OptionRows(pane: .layout, section: "Padding", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Main pane") {
                OptionRows(pane: .layout, section: "Main pane", doc: doc, settingsUI: settingsUI)
            }

            OGroup("Feedback") {
                OptionRows(pane: .layout, section: "Feedback", doc: doc, settingsUI: settingsUI)
            }

            AdditionalOptionGroups(pane: .layout, doc: doc, settingsUI: settingsUI)

            AdvancedSection(pane: .layout, settingsUI: settingsUI) {
                OGroup("Gaps and padding") {
                    OSwitchRow(LayoutPane.searchLinked.title,
                               isOn: Binding(get: { settingsUI.linkedPadding }, set: { linked in
                                   withAnimation(Motion.easeOut) { settingsUI.linkedPadding = linked }
                                   if linked { allPadding.wrappedValue = config.paddingTop }
                               }))
                    .setting(LayoutPane.searchLinked.id, settingsUI)
                    OptionRows(pane: .layout, section: "Gaps and padding", advanced: true, doc: doc,
                               settingsUI: settingsUI)
                }
                OGroup("Feedback") {
                    OptionRows(pane: .layout, section: "Feedback", advanced: true, doc: doc, settingsUI: settingsUI)
                }
                AdditionalOptionGroups(pane: .layout, advanced: true, doc: doc, settingsUI: settingsUI)
            }
        }
    }

    private var moveKeys: (left: Set<String>, right: Set<String>) {
        var left = Set<String>(), right = Set<String>()
        for submap in doc.submaps {
            for action in doc.keyActions(in: submap)
            where action.row.dispatcher == "movefocus" && action.key.count == 1 {
                if action.arg == "l" {
                    left.insert(action.key.lowercased())
                } else if action.arg == "r" {
                    right.insert(action.key.lowercased())
                }
            }
        }
        return (left, right)
    }

    private func points(_ value: Binding<CGFloat>, _ label: String) -> some View {
        OSlider(value: Binding(get: { Double(value.wrappedValue) },
                               set: { value.wrappedValue = CGFloat($0.rounded()) }),
                range: 0...60, step: 1, ticks: [10], resetValue: 10, width: 180, label: label,
                format: { "\(Int($0)) pt" })
    }

    private func move(_ layout: Layout, to target: Int) {
        let target = min(max(target, 0), doc.config.layouts.count - 1)
        guard let from = doc.config.layouts.firstIndex(of: layout), from != target else { return }
        withAnimation(Motion.snap(reduceMotion)) {
            doc.config.layouts.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        }
    }

    private func remove(_ layout: Layout) {
        guard doc.config.layouts.count > 1 else { return }
        withAnimation(Motion.snap(reduceMotion)) { doc.config.layouts.removeAll { $0 == layout } }
    }

    private func cell(_ layout: Layout) -> some View {
        let index = doc.config.layouts.firstIndex(of: layout)
        let active = index != nil
        let locked = active && doc.config.layouts.count == 1
        return LayoutCell(layout: layout, active: active) {
            withAnimation(Motion.snap(reduceMotion)) {
                if let index {
                    if !locked { doc.config.layouts.remove(at: index) }
                } else {
                    doc.config.layouts.append(layout)
                }
            }
        }
    }
}

extension LayoutPane {
    static let searchDisplays = SettingEntry(id: "layout.displays", title: "Layout per display", pane: .layout,
                                             keywords: "screen monitor current")
    static let searchCycle = SettingEntry(id: "layout.cycle", title: "Active layouts", pane: .layout,
                                          keywords: "order next previous tall wide bsp column")
    static let searchPadding = SettingEntry(id: "layout.padding", title: "Screen padding", pane: .layout,
                                            keywords: "edges margin inset")
    static let searchLinked = SettingEntry(id: "layout.linked", title: "Same padding on every side", pane: .layout,
                                           advanced: true, keywords: "top bottom left right")
}
