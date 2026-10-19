import CoreGraphics

enum FocusNavigation {
    struct Item {
        let id: CGWindowID
        let frame: CGRect
        let screen: String?
    }

    struct Relation {
        let along: CGFloat
        let across: CGFloat
        let overlaps: Bool
        let edge: CGFloat
    }

    private struct Scored {
        let id: CGWindowID
        let score: CGFloat
        let edge: CGFloat
    }

    static func relation(_ from: CGRect, _ other: CGRect, _ dir: Direction) -> Relation {
        let dx = other.midX - from.midX, dy = other.midY - from.midY
        let rows = other.minY < from.maxY && other.maxY > from.minY
        let cols = other.minX < from.maxX && other.maxX > from.minX
        switch dir {
        case .left: return Relation(along: -dx, across: dy, overlaps: rows, edge: from.minX - other.maxX)
        case .right: return Relation(along: dx, across: dy, overlaps: rows, edge: other.minX - from.maxX)
        case .upward: return Relation(along: -dy, across: dx, overlaps: cols, edge: from.minY - other.maxY)
        case .down: return Relation(along: dy, across: dx, overlaps: cols, edge: other.minY - from.maxY)
        }
    }

    static func neighbor(
        of item: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]
    ) -> CGWindowID? {
        var scored: [Scored] = []
        for other in candidates where other.id != item.id {
            let geometry = relation(item.frame, other.frame, dir)
            guard geometry.along > 1 else { continue }
            guard geometry.overlaps || other.screen != item.screen else { continue }
            scored.append(Scored(id: other.id,
                                 score: geometry.along + abs(geometry.across) * 2 + (geometry.overlaps ? 0 : 100_000),
                                 edge: geometry.overlaps ? max(0, geometry.edge) : .infinity))
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        guard let nearest = scored.map(\.edge).min(), nearest.isFinite else { return best.id }
        let adjacent = scored.filter { $0.edge <= nearest + 2 }
        let recent = adjacent.max { (stamps[$0.id] ?? 0) < (stamps[$1.id] ?? 0) }
        if let recent, stamps[recent.id] != nil { return recent.id }
        return adjacent.min(by: { $0.score < $1.score })?.id ?? best.id
    }

    static func target(
        from item: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]
    ) -> CGWindowID? {
        if let next = neighbor(of: item, dir, among: candidates, stamps: stamps) { return next }
        let here = candidates.filter { $0.id != item.id && $0.screen == item.screen }
        let behind = here.compactMap { other -> (CGWindowID, CGFloat)? in
            let geometry = relation(item.frame, other.frame, dir)
            return geometry.overlaps && geometry.along < -1 ? (other.id, -geometry.along) : nil
        }
        if let far = behind.map(\.1).max() {
            let ends = behind.filter { $0.1 >= far - 2 }.map(\.0)
            return ends.max { (stamps[$0] ?? 0) < (stamps[$1] ?? 0) }
        }
        let hereIDs = Set(here.map(\.id))
        let stack = candidates.filter {
            $0.id == item.id || (hereIDs.contains($0.id) && $0.frame.approxEqual(item.frame, tolerance: 2))
        }
        guard stack.count > 1, let i = stack.firstIndex(where: { $0.id == item.id }) else { return nil }
        let delta = dir == .left || dir == .upward ? -1 : 1
        return stack[((i + delta) % stack.count + stack.count) % stack.count].id
    }
}
