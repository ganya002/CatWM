import AppKit
import CatWMKit
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
                OSearchField(placeholder: "Search actions", text: $draft.search, focus: $searching,
                             onSubmit: pickFirstResult)
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
                    .padding(.horizontal, 8).frame(height: 34)
            }
            others
            hairline
            actions
        }
        .frame(width: Self.width)
        .surface(.medium, glass: true)
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
        .padding(.horizontal, 8).padding(.vertical, Theme.Space.small)
    }

    func modeEntry(_ mode: String) -> [String]? {
        guard !mode.isEmpty, let entry = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(entry.flags) + [ConfigDocument.capLabel(entry.key)]
    }

    @ViewBuilder var menu: some View {
        let query = draft.search.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            if query.isEmpty {
                ForEach(MenuCategory.allCases) { categoryRow($0) }
            } else {
                let hits = results(query)
                ForEach(hits) { hit in
                    OMenuRow(action: { pick(hit) }, lead: {
                        symbol(hit.symbol)
                    }, label: {
                        Text(hit.title).oneLine()
                    }, trailing: {
                        Text(MenuCategory(hit).rawValue).foregroundStyle(Theme.inkFaint).oneLine().fixedSize()
                    })
                }
                if hits.isEmpty {
                    Text("No actions match “\(query)”").foregroundStyle(Theme.inkMuted).oneLine()
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func results(_ query: String) -> [Action] {
        let words = query.lowercased().split(separator: " ")
        return Array(catalog.filter { candidate in
            let text = (candidate.title + " " + MenuCategory(candidate).rawValue).lowercased()
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

    func categoryRow(_ category: MenuCategory) -> some View {
        let current = action.map(MenuCategory.init) == category
        return OMenuRow(open: draft.open == category, action: {
            draft.open = draft.open == category ? nil : category
        }, lead: {
            symbol(category.symbol)
        }, label: {
            Text(category.rawValue).oneLine().fixedSize()
        }, trailing: {
            if current, let action {
                Text(action.title).foregroundStyle(Theme.ink).oneLine()
            }
            Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.extraSmall, .semibold))
                .foregroundStyle(Theme.inkFaint)
        })
        .onHover { if $0 { draft.open = category } }
        .anchorPreference(key: CategoryAnchor.self, value: .bounds) { [category: $0] }
        .accessibilityLabel("\(category.rawValue) actions")
    }

    func flyoutLayer(_ anchors: [MenuCategory: Anchor<CGRect>]) -> some View {
        GeometryReader { geometry in
            if let category = draft.open, let anchor = anchors[category] {
                let rect = geometry[anchor]
                flyout(category)
                    .fixedSize()
                    .offset(x: flyoutLeading ? -Self.flyoutWidth - 2 : geometry.size.width + 2, y: rect.minY - 4)
                    .transition(.opacity)
            }
        }
    }
}
