import CoreGraphics

package struct TabGroups: Equatable {
    package struct Group: Equatable {
        package let id: Int
        package var members: [CGWindowID]
        package var active: CGWindowID

        package var activeFirst: [CGWindowID] { [active] + members.filter { $0 != active } }
    }

    package private(set) var groups: [Group] = []
    package private(set) var armed: Set<CGWindowID> = []
    private var locked: Set<CGWindowID> = []
    private var nextID = 1

    package var isEmpty: Bool { groups.isEmpty }

    package func group(of id: CGWindowID) -> Group? { groups.first { $0.members.contains(id) } }

    package func isGrouped(_ id: CGWindowID) -> Bool { group(of: id) != nil }

    package func collects(_ id: CGWindowID) -> Bool {
        let members = group(of: id)?.members ?? [id]
        return members.contains(where: armed.contains) && !isLocked(id)
    }

    package func isLocked(_ id: CGWindowID) -> Bool {
        (group(of: id)?.members ?? [id]).contains(where: locked.contains)
    }

    package mutating func toggleArmed(_ id: CGWindowID) {
        if armed.remove(id) == nil { armed.insert(id) } else { locked.remove(id) }
    }

    package mutating func toggleLocked(_ id: CGWindowID) {
        let members = group(of: id)?.members ?? [id]
        if members.contains(where: locked.contains) { locked.subtract(members) } else { locked.insert(id) }
    }

    package mutating func disarm(_ members: [CGWindowID]) {
        armed.subtract(members)
        locked.subtract(members)
    }

    package func isBehind(_ id: CGWindowID) -> Bool { group(of: id).map { $0.active != id } ?? false }

    package func heir(of id: CGWindowID) -> CGWindowID? {
        guard let members = group(of: id)?.members, members.count > 1,
              let index = members.firstIndex(of: id) else { return nil }
        return members[index > 0 ? index - 1 : 1]
    }

    package func neighbor(of id: CGWindowID, offset: Int) -> CGWindowID? {
        guard let members = group(of: id)?.members, members.count > 1,
              let index = members.firstIndex(of: id) else { return nil }
        let count = members.count
        return members[((index + offset) % count + count) % count]
    }

    package mutating func join(_ id: CGWindowID, onto target: CGWindowID) {
        guard id != target else { return }
        remove(id)
        if let index = index(of: target) {
            let after = (groups[index].members.firstIndex(of: target) ?? groups[index].members.count - 1) + 1
            groups[index].members.insert(id, at: after)
            groups[index].active = id
        } else {
            groups.append(Group(id: nextID, members: [target, id], active: id))
            nextID += 1
        }
    }

    @discardableResult
    package mutating func remove(_ id: CGWindowID) -> CGWindowID? {
        guard let index = index(of: id), let position = groups[index].members.firstIndex(of: id) else { return nil }
        var group = groups[index]
        let wasArmed = group.members.contains(where: armed.contains)
        let wasLocked = group.members.contains(where: locked.contains)
        armed.remove(id)
        locked.remove(id)
        group.members.remove(at: position)
        let heir = group.members[max(0, position - 1)]
        if group.active == id { group.active = heir }
        if group.members.count < 2 {
            groups.remove(at: index)
            if wasArmed, let last = group.members.first {
                armed.insert(last)
                if wasLocked { locked.insert(last) }
            }
        } else {
            groups[index] = group
        }
        return group.active
    }

    @discardableResult
    package mutating func activate(_ id: CGWindowID) -> CGWindowID? {
        guard let index = index(of: id), groups[index].active != id else { return nil }
        let previous = groups[index].active
        groups[index].active = id
        return previous
    }

    package mutating func move(_ id: CGWindowID, to position: Int) {
        guard let index = index(of: id), let from = groups[index].members.firstIndex(of: id) else { return }
        var members = groups[index].members
        members.remove(at: from)
        members.insert(id, at: max(0, min(position, members.count)))
        groups[index].members = members
    }

    private func index(of id: CGWindowID) -> Int? { groups.firstIndex { $0.members.contains(id) } }
}
