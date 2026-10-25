import CoreGraphics

struct TabStripStack {
    enum Placement: Equatable {
        case above(CGWindowID)
        case below(CGWindowID)
    }

    private(set) var windows: [CGWindowID]

    mutating func place(_ panel: CGWindowID, below members: [CGWindowID], fallback: CGWindowID? = nil)
        -> Placement? {
        guard let top = windows.first(where: members.contains) ?? fallback else { return nil }
        guard let index = windows.firstIndex(of: top) else { return .below(top) }
        guard let under = windows.dropFirst(index + 1).first(where: { $0 != panel }),
              windows.dropFirst(index + 1).first != panel else { return nil }
        windows.removeAll { $0 == panel }
        guard let destination = windows.firstIndex(of: under) else { return nil }
        windows.insert(panel, at: destination)
        return .above(under)
    }
}
