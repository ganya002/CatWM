import AppKit
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published private(set) var items: [SwitcherItem] = []
    @Published private(set) var results: [SwitcherItem] = []
    @Published private(set) var query = ""
    @Published private(set) var appFilter: SwitcherItem?
    @Published private(set) var scope = SwitcherScope.all
    @Published private(set) var previews: [CGWindowID: NSImage] = [:]
    @Published private(set) var previewing = false
    @Published var peeking = false
    @Published var selection = 0
    @Published var shown = false
    var onPick: ((SwitcherItem) -> Void)?
    var onDismiss: (() -> Void)?
    private var icons: [pid_t: NSImage] = [:]
    private var scopes: [SwitcherScope] = SwitcherScope.allCases

    var selected: SwitcherItem? { results.indices.contains(selection) ? results[selection] : nil }
    var searching: Bool { !query.isEmpty }
    var pool: [SwitcherItem] {
        items.filter { item in scope.holds(item) && appFilter.map { $0.pid == item.pid } ?? true }
    }

    func begin(_ list: [SwitcherItem], selection start: Int, displays: Int = 1, previews shots: Bool = false) {
        items = list
        query = ""
        appFilter = nil
        scope = .all
        scopes = SwitcherScope.allCases.filter { $0 != .display || displays > 1 }
        peeking = false
        previewing = shots
        previews = previews.filter { id, _ in list.contains { $0.id == id } }
        results = list
        selection = start
        icons = Dictionary(Set(list.map(\.pid)).compactMap { pid in
            NSRunningApplication(processIdentifier: pid)?.icon.map { (pid, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func icon(_ pid: pid_t) -> NSImage? { icons[pid] }

    func setPreview(_ image: NSImage, for id: CGWindowID) {
        guard items.contains(where: { $0.id == id }) else { return }
        previews[id] = image
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta % results.count + results.count) % results.count
    }

    func type(_ text: String) {
        peeking = false
        setQuery(query + text)
    }

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

    func nextScope() {
        let index = scopes.firstIndex(of: scope) ?? 0
        scope = scopes[(index + 1) % scopes.count]
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
        results = SwitcherSearch.results(pool, query: query)
        selection = id.flatMap { id in results.firstIndex { $0.id == id } }
            ?? (id == nil ? 0 : min(index, max(results.count - 1, 0)))
    }
}

enum SwitcherScope: CaseIterable {
    case all, workspace, display

    var label: String {
        switch self {
        case .all: "All windows"
        case .workspace: "This workspace"
        case .display: "This display"
        }
    }

    func holds(_ item: SwitcherItem) -> Bool {
        switch self {
        case .all: true
        case .workspace: item.here
        case .display: item.onFocusedDisplay
        }
    }
}

struct SwitcherItem: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    var workspace = ""
    var here = false
    var onFocusedDisplay = false
    var size = CGSize.zero
}
