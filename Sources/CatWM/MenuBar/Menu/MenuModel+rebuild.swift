import AppKit
import CatWMKit
import SwiftUI

extension MenuModel {
    func rebuild() {
        items = source()
    }

    func reset() {
        query = ""
        path = []
        highlight = [:]
        appeared = false
        openWork?.cancel()
        trimWork?.cancel()
    }

    func item(_ id: String, in list: [MenuItem]? = nil) -> MenuItem? {
        for candidate in list ?? items {
            if candidate.id == id { return candidate }
            if let found = item(id, in: candidate.children) { return found }
        }
        return nil
    }

    func column(_ level: Int) -> [MenuItem] {
        if !query.isEmpty { return level == 0 ? results.map(\.item) : [] }
        guard level > 0 else { return items }
        guard level <= path.count, let parent = item(path[level - 1]) else { return [] }
        return parent.children
    }

    func hover(_ item: MenuItem, level: Int) {
        guard item.selectable else { return }
        highlight[level] = item.id
        trimWork?.cancel()
        openWork?.cancel()
        let open = path.count > level ? path[level] : nil
        if item.kind == .sub {
            guard open != item.id else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(Motion.easeOut) { self.path = Array(self.path.prefix(level)) + [item.id] }
            }
            openWork = work
            opening = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        } else if open != nil {
            let work = DispatchWorkItem { [weak self] in self?.trim(to: level) }
            trimWork = work
            trimLevel = level
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }
}
