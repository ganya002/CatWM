import CoreGraphics

struct SavedTabs: Equatable {
    struct Member: Equatable {
        let id: CGWindowID
        let pid: pid_t
    }

    let members: [Member]
    let active: CGWindowID

    init(members: [Member], active: CGWindowID) {
        self.members = members
        self.active = active
    }

    init?(_ line: String) {
        let parts = line.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let active = CGWindowID(parts[1]) else { return nil }
        let members = parts[0].split(separator: " ").compactMap { field -> Member? in
            let pair = field.split(separator: "@")
            guard pair.count == 2, let id = CGWindowID(pair[0]), let pid = pid_t(pair[1]) else { return nil }
            return Member(id: id, pid: pid)
        }
        guard members.count > 1 else { return nil }
        self.init(members: members, active: active)
    }

    var line: String { members.map { "\($0.id)@\($0.pid)" }.joined(separator: " ") + " > \(active)" }
}
