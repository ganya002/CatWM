import AppKit
import CatWMKit
import SwiftUI

struct MenuColumn: View {
    @ObservedObject var model: MenuModel
    let level: Int
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if level == 0 && model.searchable {
                OSearchField(placeholder: "Search commands…", text: $model.query, focus: $searchFocused) {
                    model.runHighlighted()
                }
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.well))
                .padding(.bottom, Theme.Space.xxs)
                .onAppear { DispatchQueue.main.async { searchFocused = true } }
                .onChange(of: model.query) { _, query in
                    model.path = []
                    model.highlight = query.isEmpty ? [:] : [0: model.results.first?.item.id ?? ""]
                }
            }
            if level == 0 && !model.query.isEmpty {
                let results = model.results
                if results.isEmpty {
                    Text("No commands match").font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(results, id: \.item.id) { result in
                                MenuRowView(model: model, item: result.item, level: 0, crumb: result.crumb)
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let rows = model.column(level).filter { !$0.hidden }
                if rows.count > 16 {
                    ScrollView { VStack(spacing: 0) { ForEach(rows) { i in row(i) } } }
                        .frame(maxHeight: 480).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rows) { i in row(i) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ i: MenuItem) -> some View {
        switch i.kind {
        case .separator:
            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.horizontal, Theme.Space.medium).padding(.vertical, 4)
        case .label:
            HStack(spacing: 6) {
                Text(i.label).oneLine()
                Spacer(minLength: 4)
                if !i.shortcut.isEmpty { Text(i.shortcut.joined()).font(Theme.keys(12, .medium)).tracking(1) }
            }
            .font(Theme.body(11.5, .medium)).foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, Theme.Space.medium).padding(.top, 8).padding(.bottom, 4)
        case .essentials:
            EssentialsRow(model: model, enabled: i.enabled)
        case .workspaces:
            let summary = WindowManager.shared.workspaceSummary()
            let highest = summary.all.compactMap { Int($0.name) }.max() ?? 0
            WorkspaceStrip(names: (1...max(9, min(highest, 10))).map(String.init), current: summary.current,
                           occupied: Set(summary.all.filter { $0.windows > 0 }.map(\.name))) { name in
                WindowManager.shared.showWorkspaceNumber(name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.refresh() }
            }
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 8)
        case .layoutPicker:
            let current = WindowManager.shared.menuBarState()?.layout
            LayoutPicker(layouts: Layout.allCases, selection: current, columns: 4) { layout in
                WindowManager.shared.dispatch("layout", layout.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.close() }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
        case .attention:
            HStack(spacing: Theme.Space.medium) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(i.label).font(Theme.body(13, .medium)).oneLine()
                Spacer(minLength: 4)
                OButton("Grant Access", variant: .primary, size: .small) { model.run(i) }
            }
            .padding(.horizontal, Theme.Space.medium).padding(.vertical, 8)
        default:
            MenuRowView(model: model, item: i, level: level)
        }
    }
}
