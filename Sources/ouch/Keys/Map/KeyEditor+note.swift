import AppKit
import SwiftUI

extension KeyEditor {
    @ViewBuilder var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            hairline
            if draft.isRange, let row = draft.row {
                note("One key of “\(doc.title(row))”", detail: "Its keys are edited together in Shortcuts")
            } else if ConfigDocument.keyName(for: code) == nil {
                note("This key can't take a shortcut yet", detail: nil)
            } else {
                OSearchField(placeholder: "Search actions", text: $draft.search, focus: $searching, onSubmit: pickFirstResult)
                    .padding(.horizontal, 2)
                hairline
                menu
                if hasArgument {
                    hairline
                    argument
                }
                hairline
                options
            }
            if let issue {
                hairline
                OStatus(kind: issue.severity == .error ? .danger : .warning, text: issue.message)
                    .tooltip(issue.message)
                    .padding(.horizontal, 8).frame(height: 34)
            }
            others
            hairline
            actions
        }
        .frame(width: Self.width)
        .surface(.md, glass: true)
        .overlayPreferenceValue(CategoryAnchor.self) { anchors in flyoutLayer(anchors) }
        .onChange(of: draft.search) { _, _ in draft.open = nil }
        .onAppear { DispatchQueue.main.async { searching = !draft.isRange } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shortcut on \(KeyHintKeyboard.legend(key))")
    }

    func note(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(Theme.body(13)).oneLine()
            if let detail { Text(detail).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine() }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
    }

    func modeEntry(_ mode: String) -> [String]? {
        guard !mode.isEmpty, let a = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
    }

    @ViewBuilder var menu: some View {
        let query = draft.search.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            if query.isEmpty {
                ForEach(MenuCategory.allCases) { categoryRow($0) }
            } else {
                let hits = results(query)
                ForEach(hits) { a in
                    OMenuRow(action: { pick(a) }) {
                        symbol(a.symbol)
                    } label: {
                        Text(a.title).oneLine()
                    } trailing: {
                        Text(MenuCategory(a).rawValue).foregroundStyle(Theme.inkFaint).oneLine().fixedSize()
                    }
                }
                if hits.isEmpty {
                    Text("No actions match “\(query)”").foregroundStyle(Theme.inkMuted).oneLine()
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func results(_ query: String) -> [Action] {
        let words = query.lowercased().split(separator: " ")
        return Array(catalog.filter { a in
            let text = (a.title + " " + MenuCategory(a).rawValue).lowercased()
            return words.allSatisfy { text.contains($0) }
        }.prefix(8))
    }

    func pickFirstResult() {
        let query = draft.search.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { save() } else if let first = results(query).first { pick(first) }
    }

    func symbol(_ name: String) -> some View {
        Image(systemName: name).font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
    }

    func categoryRow(_ c: MenuCategory) -> some View {
        let current = action.map(MenuCategory.init) == c
        return OMenuRow(open: draft.open == c, action: { draft.open = draft.open == c ? nil : c }) {
            symbol(c.symbol)
        } label: {
            Text(c.rawValue).oneLine().fixedSize()
        } trailing: {
            if current, let a = action {
                Text(a.title).foregroundStyle(Theme.accentInk).oneLine()
            }
            Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .onHover { if $0 { draft.open = c } }
        .anchorPreference(key: CategoryAnchor.self, value: .bounds) { [c: $0] }
        .accessibilityLabel("\(c.rawValue) actions")
    }

    func flyoutLayer(_ anchors: [MenuCategory: Anchor<CGRect>]) -> some View {
        GeometryReader { g in
            if let c = draft.open, let a = anchors[c] {
                let r = g[a]
                flyout(c)
                    .fixedSize()
                    .offset(x: flyoutLeading ? -Self.flyoutWidth - 2 : g.size.width + 2, y: r.minY - 4)
                    .transition(.opacity)
            }
        }
    }

}
