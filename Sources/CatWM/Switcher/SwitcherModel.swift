import CatWMKit
import CoreGraphics
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published private(set) var items: [SwitcherItem] = []
    @Published private(set) var results: [SwitcherItem] = []
    @Published private(set) var query = ""
    @Published private(set) var appFilter: SwitcherItem?
    @Published var selection = 0
    @Published var shown = false
    @Published var scrolled: CGFloat = 0
    var onPick: ((SwitcherItem) -> Void)?

    var selected: SwitcherItem? { results.indices.contains(selection) ? results[selection] : nil }
    var scope: [SwitcherItem] { appFilter.map { app in items.filter { $0.pid == app.pid } } ?? items }

    func begin(_ list: [SwitcherItem], selection start: Int) {
        items = list
        query = ""
        appFilter = nil
        results = list
        selection = start
        scrolled = 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta % results.count + results.count) % results.count
    }

    func type(_ text: String) { setQuery(query + text) }

    func erase(all: Bool) {
        guard query.isEmpty else { setQuery(all ? "" : String(query.dropLast())); return }
        guard appFilter != nil else { return }
        appFilter = nil
        refilter(keeping: selected?.id)
    }

    func toggleAppFilter() {
        appFilter = appFilter == nil ? selected : nil
        refilter(keeping: selected?.id)
    }

    func remove(where drop: (SwitcherItem) -> Bool) {
        let kept = selected?.id
        items.removeAll(where: drop)
        if let filter = appFilter, !items.contains(where: { $0.pid == filter.pid }) { appFilter = nil }
        refilter(keeping: kept)
    }

    private func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        refilter(keeping: nil)
    }

    private func refilter(keeping id: CGWindowID?) {
        let index = selection
        results = SwitcherSearch.results(scope, query: query)
        selection = id.flatMap { id in results.firstIndex { $0.id == id } }
            ?? (id == nil ? 0 : min(index, max(results.count - 1, 0)))
    }
}

struct SwitcherItem: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    var workspace = ""
}
