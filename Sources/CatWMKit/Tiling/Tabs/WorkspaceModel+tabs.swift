import CoreGraphics

package struct MaximisedTab: Equatable {
    package let workspace: String
    package let members: [CGWindowID]
}

extension WorkspaceModel {
    package mutating func hostMaximised(_ id: CGWindowID, in workspace: String) {
        if workspaceOf[id] != workspace, let group = tabs.group(of: id) {
            maximisedTabs[id] = MaximisedTab(workspace: workspace, members: group.members)
        }
        assign(id, to: workspace)
    }

    package mutating func rejoinMaximisedTabs(tabbable: (CGWindowID) -> Bool) -> [CGWindowID] {
        var rejoined: [CGWindowID] = []
        for (id, saved) in maximisedTabs.sorted(by: { $0.key < $1.key }) {
            guard let home = workspaceOf[id], home != saved.workspace else { continue }
            maximisedTabs[id] = nil
            let others = saved.members.filter { $0 != id }
            guard tabbable(id), let anchor = others.first(where: {
                workspaceOf[$0] == home && tabbable($0) && (others.count == 1 || tabs.isGrouped($0))
            }) else { continue }
            joinTab(id, onto: anchor)
            tabs.move(id, to: saved.members.firstIndex(of: id) ?? 0)
            rejoined.append(id)
        }
        return rejoined
    }

    package mutating func joinTab(_ id: CGWindowID, onto target: CGWindowID) {
        guard id != target, tabs.group(of: target)?.members.contains(id) != true else { return }
        leaveTab(id)
        let host = tabs.group(of: target)?.active ?? target
        tabs.join(id, onto: target)
        order.removeAll { $0 == id }
        order.insert(id, at: order.firstIndex(of: host) ?? order.count)
    }

    package mutating func restoreTabs(_ members: [CGWindowID], active: CGWindowID) {
        for (previous, id) in zip(members, members.dropFirst()) { joinTab(id, onto: previous) }
        if members.contains(active) { activateTab(active) }
    }

    package mutating func leaveTab(_ id: CGWindowID) {
        guard let group = tabs.group(of: id), let heir = tabs.remove(id) else { return }
        if group.active == id { swapOrder(id, heir) }
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: order.firstIndex(of: heir).map { $0 + 1 } ?? order.count)
    }

    package mutating func activateTab(_ id: CGWindowID) {
        guard let previous = tabs.activate(id) else { return }
        swapOrder(previous, id)
    }

    private mutating func swapOrder(_ first: CGWindowID, _ second: CGWindowID) {
        guard let i = order.firstIndex(of: first), let j = order.firstIndex(of: second) else { return }
        order.swapAt(i, j)
    }
}
