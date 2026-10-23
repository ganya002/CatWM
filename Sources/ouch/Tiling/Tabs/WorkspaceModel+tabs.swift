import CoreGraphics

extension WorkspaceModel {
    mutating func joinTab(_ id: CGWindowID, onto target: CGWindowID) {
        guard id != target, tabs.group(of: target)?.members.contains(id) != true else { return }
        leaveTab(id)
        let host = tabs.group(of: target)?.active ?? target
        tabs.join(id, onto: target)
        order.removeAll { $0 == id }
        order.insert(id, at: order.firstIndex(of: host) ?? order.count)
    }

    mutating func restoreTabs(_ members: [CGWindowID], active: CGWindowID) {
        for (previous, id) in zip(members, members.dropFirst()) { joinTab(id, onto: previous) }
        if members.contains(active) { activateTab(active) }
    }

    mutating func leaveTab(_ id: CGWindowID) {
        guard let group = tabs.group(of: id), let heir = tabs.remove(id) else { return }
        if group.active == id { swapOrder(id, heir) }
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: order.firstIndex(of: heir).map { $0 + 1 } ?? order.count)
    }

    mutating func activateTab(_ id: CGWindowID) {
        guard let previous = tabs.activate(id) else { return }
        swapOrder(previous, id)
    }

    private mutating func swapOrder(_ first: CGWindowID, _ second: CGWindowID) {
        guard let i = order.firstIndex(of: first), let j = order.firstIndex(of: second) else { return }
        order.swapAt(i, j)
    }
}
