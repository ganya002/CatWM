import AppKit
import CatWMKit
import SwiftUI

extension MenuModel {
    func unhover(_ item: MenuItem, level: Int) {
        if opening == item.id { openWork?.cancel(); opening = nil }
        let open = path.count > level ? path[level] : nil
        if highlight[level] == item.id, open != item.id { highlight[level] = nil }
    }

    func enterColumn(_ level: Int) {
        if level > trimLevel { trimWork?.cancel() }
        if level > 0, level <= path.count { highlight[level - 1] = path[level - 1] }
    }

    func trim(to level: Int) {
        guard path.count > level else { return }
        withAnimation(Motion.easeOut) { path = Array(path.prefix(level)) }
        for deeper in highlight.keys where deeper > level { highlight[deeper] = nil }
    }

    func move(_ delta: Int) {
        openWork?.cancel()
        trimWork?.cancel()
        let level = keyLevel
        let list = column(level).filter { query.isEmpty ? $0.selectable : true }
        guard !list.isEmpty else { return }
        let current = highlight[level].flatMap { id in list.firstIndex { $0.id == id } }
        let next = current.map { ($0 + delta + list.count) % list.count } ?? (delta > 0 ? 0 : list.count - 1)
        highlight[level] = list[next].id
        if query.isEmpty { trim(to: level) }
    }

    func openHighlighted() {
        let level = keyLevel
        guard query.isEmpty, let id = highlight[level], let i = item(id), i.kind == .sub, i.enabled else { return }
        withAnimation(Motion.easeOut) { path = Array(path.prefix(level)) + [id] }
        highlight[level + 1] = i.children.first(where: \.selectable)?.id
    }

    func back() -> Bool {
        let level = keyLevel
        guard level > 0 else { return false }
        highlight[level] = nil
        trim(to: level - 1)
        return true
    }

    func runHighlighted() {
        let level = keyLevel
        if !query.isEmpty {
            let list = results.map(\.item)
            if let i = list.first(where: { $0.id == highlight[0] }) ?? list.first { run(i) }
            return
        }
        guard let id = highlight[level], let i = item(id) else { return }
        if i.kind == .sub { openHighlighted() } else { run(i) }
    }

    func run(_ item: MenuItem) {
        guard item.enabled, let action = item.action else { return }
        if item.kind == .action || item.kind == .check {
            Tips.shared.clicked(id: item.id, label: item.label, shortcut: item.shortcut)
        }
        if item.keepOpen {
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
        } else {
            close()
            DispatchQueue.main.async { action() }
        }
    }

    func refresh() {
        items = source()
    }
}
